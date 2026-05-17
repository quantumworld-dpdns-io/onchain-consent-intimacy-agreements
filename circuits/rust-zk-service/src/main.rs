mod config;
mod error;
mod noir;
mod risc_zero;
mod types;
mod api;

use actix_web::{web, App, HttpServer, middleware};
use tracing_subscriber;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("rust_zk_service=info")
        .init();

    let cfg = config::Config::from_env();
    let noir_prover = noir::NoirProver::new(&cfg)?;
    let risc_zero_prover = risc_zero::RiscZeroProver::new(&cfg)?;

    let cfg_data = web::Data::new(cfg);
    let noir_data = web::Data::new(noir_prover);
    let rz_data = web::Data::new(risc_zero_prover);

    tracing::info!("Starting Rust ZK service on {}:{}", cfg_data.host, cfg_data.port);

    HttpServer::new(move || {
        App::new()
            .app_data(cfg_data.clone())
            .app_data(noir_data.clone())
            .app_data(rz_data.clone())
            .configure(api::configure_routes)
            .wrap(middleware::Logger::default())
    })
    .bind(format!("{}:{}", cfg_data.host, cfg_data.port))?
    .run()
    .await
}
