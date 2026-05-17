use thiserror::Error;

#[derive(Error, Debug)]
pub enum ZkError {
    #[error("Circuit compilation failed: {0}")]
    CompilationError(String),
    #[error("Proof generation failed: {0}")]
    ProofGenerationError(String),
    #[error("Proof verification failed: {0}")]
    VerificationError(String),
    #[error("Invalid input: {0}")]
    InvalidInput(String),
    #[error("Unsupported proof type: {0}")]
    UnsupportedProofType(String),
    #[error("Internal error: {0}")]
    Internal(String),
    #[error("Prover not configured: {0}")]
    ProverNotConfigured(String),
}

impl From<ZkError> for actix_web::Error {
    fn from(e: ZkError) -> Self {
        actix_web::error::ErrorInternalServerError(e.to_string())
    }
}
