use std::time::Instant;

use crate::error::ZkError;
use crate::types::{ProofRequest, ProofResponse, ProofType};

pub struct RiscZeroProver {
    guest_elf_path: std::path::PathBuf,
    image_id: Option<String>,
    cache: std::collections::HashMap<String, String>,
}

impl RiscZeroProver {
    pub fn new(cfg: &crate::config::Config) -> Result<Self, ZkError> {
        let guest_elf_path = std::path::PathBuf::from("circuits/risc-zero/target/guest");
        let image_id = None;

        if !guest_elf_path.exists() {
            tracing::warn!(
                "RISC Zero guest ELF directory not found at {:?}",
                guest_elf_path
            );
        }

        Ok(Self {
            guest_elf_path,
            image_id,
            cache: std::collections::HashMap::with_capacity(cfg.proof_cache_size),
        })
    }

    pub async fn generate_proof(&self, request: &ProofRequest) -> Result<ProofResponse, ZkError> {
        let start = Instant::now();
        let circuit_name = match &request.proof_type {
            ProofType::ConsentAge => "consent_age",
            ProofType::PartyInclusion => "party_inclusion",
            ProofType::ScopeInclusion => "scope_inclusion",
            ProofType::WorkflowCompliance => "workflow_compliance",
            ProofType::Custom(name) => name.as_str(),
        };

        let elf_path = self.guest_elf_path.join(format!("{}.elf", circuit_name));
        if !elf_path.exists() {
            return Err(ZkError::CompilationError(format!(
                "Guest ELF not found at {:?}",
                elf_path
            )));
        }

        let cache_key = format!("rz:{}:{}", circuit_name, request.public_inputs.join(","));
        if let Some(cached) = self.cache.get(&cache_key) {
            return Ok(ProofResponse {
                proof: cached.clone(),
                public_inputs: request.public_inputs.clone(),
                proof_type: request.proof_type.clone(),
                circuit_size: Some(0),
                proving_time_ms: 0,
            });
        }

        let proof_hex = tokio::task::spawn_blocking({
            let elf = elf_path.clone();
            let pub_inputs = request.public_inputs.clone();
            let priv_inputs = request.private_inputs.clone();
            move || {
                let elf_bytes = std::fs::read(&elf)
                    .map_err(|e| format!("Failed to read ELF: {}", e))?;

                let env = build_guest_env(&pub_inputs, &priv_inputs);

                let receipt = risc_zero_zkvm_prove(&elf_bytes, &env)
                    .map_err(|e| format!("RISC Zero prove failed: {}", e))?;

                let receipt_bytes = bincode::serialize(&receipt)
                    .map_err(|e| format!("Failed to serialize receipt: {}", e))?;

                Ok::<Vec<u8>, String>(receipt_bytes)
            }
        })
        .await
        .map_err(|e| ZkError::ProofGenerationError(format!("Join error: {}", e)))?
        .map_err(|e| ZkError::ProofGenerationError(e))?;

        let proof_hex_str = hex::encode(&proof_hex);
        let elapsed = start.elapsed().as_millis() as u64;

        let mut cache = self.cache.clone();
        if cache.len() < cache.capacity() {
            cache.insert(cache_key, proof_hex_str.clone());
        }

        Ok(ProofResponse {
            proof: proof_hex_str,
            public_inputs: request.public_inputs.clone(),
            proof_type: request.proof_type.clone(),
            circuit_size: Some(proof_hex.len() as u32),
            proving_time_ms: elapsed,
        })
    }

    pub async fn verify_proof(&self, proof: &str, image_id: &str) -> Result<bool, ZkError> {
        let start = Instant::now();

        let proof_bytes = hex::decode(proof)
            .map_err(|e| ZkError::InvalidInput(format!("Invalid proof hex: {}", e)))?;

        let receipt: Vec<u8> = bincode::deserialize(&proof_bytes)
            .map_err(|e| ZkError::VerificationError(format!("Failed to deserialize receipt: {}", e)))?;

        let valid = tokio::task::spawn_blocking(move || {
            risc_zero_zkvm_verify(&receipt, image_id)
        })
        .await
        .map_err(|e| ZkError::VerificationError(format!("Join error: {}", e)))?
        .map_err(|e| ZkError::VerificationError(format!("Verification failed: {}", e)))?;

        let elapsed = start.elapsed().as_millis() as u64;
        tracing::info!("RISC Zero verification completed in {}ms", elapsed);

        Ok(valid)
    }
}

fn build_guest_env(public_inputs: &[String], private_inputs: &[String]) -> Vec<u8> {
    let mut env = Vec::new();
    for input in public_inputs.iter().chain(private_inputs) {
        let bytes = input.as_bytes();
        let len = (bytes.len() as u32).to_le_bytes();
        env.extend_from_slice(&len);
        env.extend_from_slice(bytes);
    }
    env
}

fn risc_zero_zkvm_prove(_elf_bytes: &[u8], _env: &[u8]) -> Result<Vec<u8>, String> {
    Err("RISC Zero guest execution not available: compile with risc0-zkvm feature".to_string())
}

fn risc_zero_zkvm_verify(_receipt: &[u8], _image_id: &str) -> Result<bool, String> {
    Err("RISC Zero verification not available: compile with risc0-zkvm feature".to_string())
}
