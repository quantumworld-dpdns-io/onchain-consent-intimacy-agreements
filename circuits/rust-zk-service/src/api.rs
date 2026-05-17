use actix_web::{web, HttpResponse};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

use crate::types::*;

static TOTAL_PROOFS: AtomicU64 = AtomicU64::new(0);
static TOTAL_VERIFICATIONS: AtomicU64 = AtomicU64::new(0);
static START_TIME: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();

pub struct AppState {
    pub cfg: web::Data<crate::config::Config>,
    pub noir_prover: web::Data<crate::noir::NoirProver>,
    pub risc_zero_prover: web::Data<crate::risc_zero::RiscZeroProver>,
}

pub fn configure_routes(cfg: &mut web::ServiceConfig) {
    START_TIME.get_or_init(Instant::now);
    cfg.service(
        web::scope("/api/v1/proof")
            .route("/generate", web::post().to(generate_proof))
            .route("/verify", web::post().to(verify_proof))
            .route("/health", web::get().to(health)),
    );
}

async fn generate_proof(
    app: web::Data<AppState>,
    body: web::Json<ProofRequest>,
) -> HttpResponse {
    if !app.cfg.allowed_proof_types.is_empty() {
        let type_str = body.proof_type.to_string();
        if !app.cfg.allowed_proof_types.iter().any(|t| type_str.contains(t)) {
            return HttpResponse::BadRequest().json(serde_json::json!({
                "error": format!("Unsupported proof type: {}", type_str)
            }));
        }
    }

    let result = match body.proof_type {
        ProofType::ConsentAge
        | ProofType::PartyInclusion
        | ProofType::ScopeInclusion
        | ProofType::WorkflowCompliance => {
            app.noir_prover.generate_proof(&body).await
        }
        ProofType::Custom(_) => {
            app.risc_zero_prover.generate_proof(&body).await
        }
    };

    TOTAL_PROOFS.fetch_add(1, Ordering::SeqCst);

    match result {
        Ok(response) => HttpResponse::Ok().json(response),
        Err(e) => {
            tracing::error!("Proof generation failed: {}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": e.to_string()
            }))
        }
    }
}

async fn verify_proof(
    app: web::Data<AppState>,
    body: web::Json<VerificationRequest>,
) -> HttpResponse {
    let start = Instant::now();

    let result = match body.proof_type {
        ProofType::ConsentAge
        | ProofType::PartyInclusion
        | ProofType::ScopeInclusion
        | ProofType::WorkflowCompliance => {
            app.noir_prover
                .verify_proof(&body.proof, &body.public_inputs, &body.proof_type.to_string())
                .await
        }
        ProofType::Custom(_) => {
            app.risc_zero_prover
                .verify_proof(&body.proof, "")
                .await
        }
    };

    TOTAL_VERIFICATIONS.fetch_add(1, Ordering::SeqCst);
    let elapsed = start.elapsed().as_millis() as u64;

    match result {
        Ok(valid) => HttpResponse::Ok().json(VerificationResponse {
            valid,
            verification_time_ms: elapsed,
        }),
        Err(e) => {
            tracing::error!("Proof verification failed: {}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": e.to_string()
            }))
        }
    }
}

async fn health() -> HttpResponse {
    let uptime = START_TIME
        .get()
        .map(|t| t.elapsed().as_secs())
        .unwrap_or(0);

    HttpResponse::Ok().json(ProverStatus {
        noir_available: true,
        risc_zero_available: false,
        uptime_seconds: uptime,
        total_proofs_generated: TOTAL_PROOFS.load(Ordering::SeqCst),
        total_verifications: TOTAL_VERIFICATIONS.load(Ordering::SeqCst),
        cache_size: 0,
    })
}
