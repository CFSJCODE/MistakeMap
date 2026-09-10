mod config;
mod db;
mod routes;
mod storage;

use std::net::SocketAddr;
use std::sync::Arc;

use axum::routing::get;
use axum::Router;
use sqlx::PgPool;

use config::Config;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub storage: aws_sdk_s3::Client,
    pub config: Arc<Config>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info".into()),
        )
        .init();

    dotenvy::dotenv().ok();
    let config = Config::from_env().map_err(|e| {
        tracing::error!("configuração inválida: {e}");
        e
    })?;

    tracing::info!("conectando ao Postgres...");
    let db = db::connect(&config.database_url).await?;
    db::ping(&db).await?;
    tracing::info!("Postgres OK");

    tracing::info!("conectando ao Cloudflare R2 (bucket: {})...", config.r2_bucket);
    let storage = storage::build_client(&config);
    storage::ping(&storage, &config.r2_bucket).await?;
    tracing::info!("R2 OK");

    let state = AppState {
        db,
        storage,
        config: Arc::new(config.clone()),
    };

    let app = Router::new()
        .route("/health", get(routes::health::health))
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    tracing::info!("worker escutando em http://{addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
