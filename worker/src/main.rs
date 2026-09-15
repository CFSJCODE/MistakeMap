mod attempts;
mod config;
mod db;
mod quota;
mod routes;
mod storage;

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use axum::routing::{get, post};
use axum::Router;
use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

use config::Config;

// Quantas tentativas o worker pega por rodada.
const BATCH_SIZE: i64 = 5;
// Intervalo entre cada rodada de polling.
const POLL_INTERVAL: Duration = Duration::from_secs(10);

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

    // O loop de polling roda em paralelo com o servidor HTTP.
    // Clonamos o que precisa porque state.db/storage/config implementam Clone
    // (PgPool e aws Client são internamente Arc, então clone é barato).
    let poll_db = state.db.clone();
    let poll_storage = state.storage.clone();
    let poll_config = state.config.clone();
    let poll_handle = tokio::spawn(async move {
        run_poll_loop(poll_db, poll_storage, poll_config).await;
    });

    let app = Router::new()
        .route("/health", get(routes::health::health))
        .route("/upload-url", post(routes::upload_url::upload_url))
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    tracing::info!("worker escutando em http://{addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;

    // tokio::select! corre as duas futures ao mesmo tempo e encerra quando
    // qualquer uma delas terminar. Assim, se o loop travar ou o servidor
    // parar, o processo todo encerra de forma limpa.
    tokio::select! {
        result = axum::serve(listener, app) => {
            if let Err(e) = result {
                tracing::error!("servidor HTTP encerrou com erro: {e}");
            }
        }
        _ = poll_handle => {
            tracing::error!("loop de polling encerrou inesperadamente");
        }
    }

    Ok(())
}

// Loop de polling: acorda a cada POLL_INTERVAL, busca tentativas pendentes
// e as processa. Nunca retorna em condições normais.
async fn run_poll_loop(
    db: PgPool,
    storage: aws_sdk_s3::Client,
    config: Arc<Config>,
) {
    let mut interval = tokio::time::interval(POLL_INTERVAL);

    loop {
        // O primeiro tick() retorna imediatamente (t=0), depois a cada 10s.
        interval.tick().await;

        match attempts::fetch_pending(&db, BATCH_SIZE).await {
            Err(e) => {
                // Erro de banco não encerra o loop — logamos e tentamos na
                // próxima rodada. Isso cobre quedas temporárias de conexão.
                tracing::error!("erro ao buscar tentativas pendentes: {e}");
            }
            Ok(rows) if rows.is_empty() => {
                tracing::debug!("nenhuma tentativa pendente");
            }
            Ok(rows) => {
                tracing::info!("{} tentativa(s) encontrada(s)", rows.len());
                for row in rows {
                    process_attempt(&db, &storage, &config, row).await;
                }
            }
        }
    }
}

async fn process_attempt(
    db: &PgPool,
    storage: &aws_sdk_s3::Client,
    config: &Config,
    row: attempts::AttemptRow,
) {
    tracing::info!(attempt_id = %row.id, "iniciando processamento");

    // 1. Buscar a lista de assets associados à tentativa.
    let assets = match attempts::fetch_assets(db, row.id).await {
        Ok(a) => a,
        Err(e) => {
            tracing::error!(attempt_id = %row.id, "erro ao buscar assets: {e}");
            mark_failed_logged(db, &row).await;
            return;
        }
    };

    if assets.is_empty() {
        tracing::warn!(attempt_id = %row.id, "tentativa sem assets — pulando");
        return;
    }

    // 2. Baixar cada asset do R2.
    for asset in &assets {
        tracing::info!(
            attempt_id = %row.id,
            asset_id = %asset.id,
            path = %asset.object_path,
            "baixando asset"
        );

        // Verifica cota Class B antes de cada GET no R2.
        if let Err(e) = quota::check_class_b(db).await {
            tracing::warn!(attempt_id = %row.id, "download bloqueado por cota R2: {e}");
            mark_failed_logged(db, &row).await;
            return;
        }

        match storage::download_asset(storage, &config.r2_bucket, &asset.object_path).await {
            Ok(bytes) => {
                let byte_count = bytes.len() as i64;
                tracing::info!(
                    attempt_id = %row.id,
                    asset_id = %asset.id,
                    bytes = byte_count,
                    "asset baixado com sucesso"
                );

                // Registra a operação Class B e o tamanho transferido.
                if let Err(e) = quota::increment_class_b(db).await {
                    tracing::error!("falha ao incrementar cota Class B: {e}");
                }
                if let Err(e) = quota::add_storage_bytes(db, byte_count).await {
                    tracing::error!("falha ao registrar bytes de storage: {e}");
                }

                // TODO (Fase P1): passar `bytes` para o módulo de OCR.
                let _ = bytes;
            }
            Err(e) => {
                tracing::error!(attempt_id = %row.id, asset_id = %asset.id, "falha ao baixar asset: {e}");
                mark_failed_logged(db, &row).await;
                return;
            }
        }
    }

    // TODO (Fase P1): chamar OCR → salvar ocr_artifacts → chamar LLM → gravar error_events.
    // Por ora, todos os assets foram baixados com sucesso: marcamos como completed.
    mark_completed_logged(db, &row).await;
}

// Marca como completed e loga o resultado sem propagar erro.
async fn mark_completed_logged(db: &PgPool, row: &attempts::AttemptRow) {
    match attempts::mark_completed(db, row.id, row.version).await {
        Ok(true) => tracing::info!(attempt_id = %row.id, "marcado como completed"),
        Ok(false) => tracing::warn!(attempt_id = %row.id, "versão divergiu — outra instância completou antes"),
        Err(e) => tracing::error!(attempt_id = %row.id, "erro ao marcar como completed: {e}"),
    }
}

// Marca como retryable_failed e loga o resultado sem propagar erro.
async fn mark_failed_logged(db: &PgPool, row: &attempts::AttemptRow) {
    match attempts::mark_failed(db, row.id, row.version).await {
        Ok(true) => tracing::warn!(attempt_id = %row.id, "marcado como retryable_failed"),
        Ok(false) => tracing::warn!(attempt_id = %row.id, "versão divergiu — outra instância processou"),
        Err(e) => tracing::error!(attempt_id = %row.id, "erro ao marcar como failed: {e}"),
    }
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
