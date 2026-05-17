use std::path::PathBuf;
use std::process::Command;
use std::time::Instant;

use crate::error::ZkError;
use crate::types::{ProofRequest, ProofResponse, ProofType};

pub struct NoirProver {
    binary_path: String,
    circuits_dir: PathBuf,
    cache: std::collections::HashMap<String, String>,
}

impl NoirProver {
    pub fn new(cfg: &crate::config::Config) -> Result<Self, ZkError> {
        let circuits_dir = PathBuf::from("circuits/noir");
        if !circuits_dir.exists() {
            tracing::warn!("Noir circuits directory not found at {:?}", circuits_dir);
        }
        Ok(Self {
            binary_path: cfg.noir_binary_path.clone(),
            circuits_dir,
            cache: std::collections::HashMap::with_capacity(cfg.proof_cache_size),
        })
    }

    fn circuit_name_for_type(proof_type: &ProofType) -> &str {
        match proof_type {
            ProofType::ConsentAge => "consent_age",
            ProofType::PartyInclusion => "party_inclusion",
            ProofType::ScopeInclusion => "scope_inclusion",
            ProofType::WorkflowCompliance => "workflow_compliance",
            ProofType::Custom(name) => name.as_str(),
        }
    }

    pub async fn generate_proof(&self, request: &ProofRequest) -> Result<ProofResponse, ZkError> {
        let start = Instant::now();
        let circuit_name = Self::circuit_name_for_type(&request.proof_type);
        let circuit_path = self.circuits_dir.join(circuit_name);

        if !circuit_path.exists() {
            return Err(ZkError::CompilationError(format!(
                "Circuit not found at {:?}",
                circuit_path
            )));
        }

        let cache_key = format!("{}:{}", circuit_name, request.public_inputs.join(","));
        if let Some(cached_proof) = self.cache.get(&cache_key) {
            return Ok(ProofResponse {
                proof: cached_proof.clone(),
                public_inputs: request.public_inputs.clone(),
                proof_type: request.proof_type.clone(),
                circuit_size: None,
                proving_time_ms: 0,
            });
        }

        let prover_toml_path = circuit_path.join("Prover.toml");
        let prover_toml_content = self.build_prover_toml(&request.public_inputs, &request.private_inputs);
        tokio::fs::write(&prover_toml_path, &prover_toml_content)
            .await
            .map_err(|e| ZkError::Internal(format!("Failed to write Prover.toml: {}", e)))?;

        let output = tokio::task::spawn_blocking({
            let binary = self.binary_path.clone();
            let cpath = circuit_path.clone();
            move || {
                Command::new(&binary)
                    .arg("execute")
                    .arg("--package")
                    .arg(circuit_name)
                    .current_dir(&cpath)
                    .output()
            }
        })
        .await
        .map_err(|e| ZkError::ProofGenerationError(format!("Join error: {}", e)))?
        .map_err(|e| ZkError::ProofGenerationError(format!("Execution failed: {}", e)))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ZkError::ProofGenerationError(format!(
                "nargo execute failed: {}",
                stderr
            )));
        }

        let bb_output = tokio::task::spawn_blocking({
            let binary = self.binary_path.clone();
            let cpath = circuit_path.clone();
            move || {
                Command::new(&binary)
                    .arg("prove")
                    .arg("--package")
                    .arg(circuit_name)
                    .current_dir(&cpath)
                    .output()
            }
        })
        .await
        .map_err(|e| ZkError::ProofGenerationError(format!("Join error: {}", e)))?
        .map_err(|e| ZkError::ProofGenerationError(format!("BB prove failed: {}", e)))?;

        if !bb_output.status.success() {
            let stderr = String::from_utf8_lossy(&bb_output.stderr);
            return Err(ZkError::ProofGenerationError(format!(
                "Barretenberg prove failed: {}",
                stderr
            )));
        }

        let proof_path = circuit_path.join("proofs").join(format!("{}.proof", circuit_name));
        let proof_hex = tokio::fs::read_to_string(&proof_path)
            .await
            .map_err(|e| ZkError::ProofGenerationError(format!("Failed to read proof: {}", e)))?;

        let elapsed = start.elapsed().as_millis() as u64;

        if self.cache.len() < self.cache.capacity() {
            let mut cache = self.cache.clone();
            cache.insert(cache_key, proof_hex.clone());
        }

        Ok(ProofResponse {
            proof: proof_hex,
            public_inputs: request.public_inputs.clone(),
            proof_type: request.proof_type.clone(),
            circuit_size: None,
            proving_time_ms: elapsed,
        })
    }

    pub async fn verify_proof(
        &self,
        proof: &str,
        public_inputs: &[String],
        proof_type: &str,
    ) -> Result<bool, ZkError> {
        let start = Instant::now();
        let circuit_path = self.circuits_dir.join(proof_type);

        if !circuit_path.exists() {
            return Err(ZkError::VerificationError(format!(
                "Circuit not found for type: {}",
                proof_type
            )));
        }

        let proof_bytes = hex::decode(proof)
            .map_err(|e| ZkError::InvalidInput(format!("Invalid proof hex: {}", e)))?;

        let proof_file = circuit_path.join("proofs").join(format!("{}.proof", proof_type));
        tokio::fs::write(&proof_file, &proof_bytes)
            .await
            .map_err(|e| ZkError::Internal(format!("Failed to write proof file: {}", e)))?;

        let output = tokio::task::spawn_blocking({
            let binary = self.binary_path.clone();
            let cpath = circuit_path.clone();
            move || {
                Command::new(&binary)
                    .arg("verify")
                    .arg("--package")
                    .arg(proof_type)
                    .current_dir(&cpath)
                    .output()
            }
        })
        .await
        .map_err(|e| ZkError::VerificationError(format!("Join error: {}", e)))?
        .map_err(|e| ZkError::VerificationError(format!("Verify command failed: {}", e)))?;

        let elapsed = start.elapsed().as_millis() as u64;
        tracing::info!("Noir verification completed in {}ms", elapsed);

        Ok(output.status.success())
    }

    fn build_prover_toml(&self, public_inputs: &[String], private_inputs: &[String]) -> String {
        let mut toml = String::new();
        for (i, input) in public_inputs.iter().enumerate() {
            toml.push_str(&format!("pub_input_{} = \"{}\"\n", i, input));
        }
        for (i, input) in private_inputs.iter().enumerate() {
            toml.push_str(&format!("priv_input_{} = \"{}\"\n", i, input));
        }
        toml
    }
}
