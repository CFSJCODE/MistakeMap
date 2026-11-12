mod attempts;
mod config;
mod db;
mod pipeline;
mod quota;
mod routes;
mod storage;

use std::net::SocketAddr;
use std::sync::Arc;

use axum::routing::{get, post};
use axum::Router;
use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

use config::Config;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub storage: aws_sdk_s3::Client,
    pub config: Arc<Config>,
    // Chave pública ES256 carregada do JWKS do Supabase na inicialização.
    // Arc porque DecodingKey não é Copy, mas é barata de clonar via ponteiro.
    pub jwt_key: Arc<DecodingKey>,
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

    // Busca a chave pública do Supabase para validar JWTs ES256.
    // Fazemos isso UMA VEZ na inicialização em vez de a cada requisição:
    // evita latência de rede no caminho crítico e funciona mesmo se o
    // endpoint JWKS ficar temporariamente indisponível depois do boot.
    tracing::info!("buscando chave pública JWT do Supabase...");
    let jwt_key = fetch_jwks(&config.supabase_url).await?;
    tracing::info!("chave JWT carregada");

    let state = AppState {
        db,
        storage,
        config: Arc::new(config.clone()),
        jwt_key: Arc::new(jwt_key),
    };

    // O worker não mantém mais um loop de polling próprio: a cadência do
    // pipeline vem de fora, do pg_cron chamando POST /process-batch via pg_net.
    // Assim o processo pode escalar a zero entre execuções, que é o que torna
    // viável hospedá-lo num plano gratuito sem manter uma VM ligada 24/7.
    let app = Router::new()
        .route("/health", get(routes::health::health))
        .route("/upload-url", post(routes::upload_url::upload_url))
        .route("/process-batch", post(routes::process_batch::process_batch))
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    tracing::info!("worker escutando em http://{addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;

    axum::serve(listener, app).await?;

    // Sair do serve é sempre anormal. Retornar Err encerra o processo com
    // código != 0, para o supervisor da plataforma reiniciar em vez de tratar
    // como encerramento limpo e deixar o serviço fora do ar.
    Err("servidor HTTP encerrou inesperadamente".into())
}

// Busca o conjunto de chaves públicas (JWKS) do Supabase e retorna a
// DecodingKey da primeira chave EC encontrada.
//
// O Supabase expõe o endpoint público:
//   {SUPABASE_URL}/auth/v1/.well-known/jwks.json
//
// Por que só pegamos a primeira chave?
// Para o MVP, o Supabase tem uma única chave ativa. Se no futuro houver
// rotação de chave, basta reiniciar o worker para ele pegar a nova.
async fn fetch_jwks(supabase_url: &str) -> Result<DecodingKey, Box<dyn std::error::Error>> {
    let url = format!("{}/auth/v1/.well-known/jwks.json", supabase_url.trim_end_matches('/'));

    // JwkSet é o tipo do jsonwebtoken que representa o JSON {"keys": [...]}
    let jwks: jsonwebtoken::jwk::JwkSet = reqwest::get(&url).await?.json().await?;

    let jwk = jwks
        .keys
        .into_iter()
        .next()
        .ok_or("JWKS vazio: nenhuma chave encontrada")?;

    // DecodingKey::from_jwk converte o JWK (com x, y, kty, crv) em uma chave
    // que o jsonwebtoken consegue usar para verificar assinaturas ES256.
    let key = DecodingKey::from_jwk(&jwk)?;
    Ok(key)
}
