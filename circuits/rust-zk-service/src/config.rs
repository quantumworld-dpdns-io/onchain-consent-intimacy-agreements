use std::env;
use std::net::IpAddr;

#[derive(Debug, Clone)]
pub struct Config {
    pub host: IpAddr,
    pub port: u16,
    pub noir_binary_path: String,
    pub risc_zero_binary_path: Option<String>,
    pub proof_cache_size: usize,
    pub max_proof_time_ms: u64,
    pub allowed_proof_types: Vec<String>,
}

impl Config {
    pub fn from_env() -> Self {
        let host: IpAddr = env::var("HOST")
            .unwrap_or_else(|_| "0.0.0.0".to_string())
            .parse()
            .expect("HOST must be a valid IP address");

        let port: u16 = env::var("PORT")
            .unwrap_or_else(|_| "3000".to_string())
            .parse()
            .expect("PORT must be a valid u16");

        let noir_binary_path = env::var("NOIR_BINARY_PATH")
            .unwrap_or_else(|_| "nargo".to_string());

        let risc_zero_binary_path = env::var("RISC_ZERO_BINARY_PATH").ok();

        let proof_cache_size: usize = env::var("PROOF_CACHE_SIZE")
            .unwrap_or_else(|_| "100".to_string())
            .parse()
            .expect("PROOF_CACHE_SIZE must be a valid usize");

        let max_proof_time_ms: u64 = env::var("MAX_PROOF_TIME_MS")
            .unwrap_or_else(|_| "30000".to_string())
            .parse()
            .expect("MAX_PROOF_TIME_MS must be a valid u64");

        let allowed_proof_types = env::var("ALLOWED_PROOF_TYPES")
            .unwrap_or_else(|_| "ConsentAge,PartyInclusion,ScopeInclusion,WorkflowCompliance".to_string())
            .split(',')
            .map(|s| s.trim().to_string())
            .collect();

        Self {
            host,
            port,
            noir_binary_path,
            risc_zero_binary_path,
            proof_cache_size,
            max_proof_time_ms,
            allowed_proof_types,
        }
    }
}
