use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofRequest {
    pub consent_id: String,
    pub proof_type: ProofType,
    pub public_inputs: Vec<String>,
    pub private_inputs: Vec<String>,
    pub chain: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ProofType {
    ConsentAge,
    PartyInclusion,
    ScopeInclusion,
    WorkflowCompliance,
    Custom(String),
}

impl std::fmt::Display for ProofType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProofType::ConsentAge => write!(f, "ConsentAge"),
            ProofType::PartyInclusion => write!(f, "PartyInclusion"),
            ProofType::ScopeInclusion => write!(f, "ScopeInclusion"),
            ProofType::WorkflowCompliance => write!(f, "WorkflowCompliance"),
            ProofType::Custom(s) => write!(f, "Custom({})", s),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofResponse {
    pub proof: String,
    pub public_inputs: Vec<String>,
    pub proof_type: ProofType,
    pub circuit_size: Option<u32>,
    pub proving_time_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationRequest {
    pub proof: String,
    pub public_inputs: Vec<String>,
    pub proof_type: ProofType,
    pub verifier_contract: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationResponse {
    pub valid: bool,
    pub verification_time_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProverStatus {
    pub noir_available: bool,
    pub risc_zero_available: bool,
    pub uptime_seconds: u64,
    pub total_proofs_generated: u64,
    pub total_verifications: u64,
    pub cache_size: usize,
}
