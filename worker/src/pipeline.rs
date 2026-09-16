use sqlx::PgPool;

use crate::attempts;
use crate::config::Config;
use crate::quota;
use crate::storage;

// Quantas tentativas o worker processa por chamada.
//
// Mantido baixo de propósito: cada invocação precisa terminar dentro do timeout
// de requisição da plataforma (Cloud Run: 300s por padrão). Um lote pequeno
// executando com frequência é mais previsível que um lote grande e raro.
pub const BATCH_SIZE: i64 = 5;

#[derive(Debug, Default, serde::Serialize)]
pub struct BatchSummary {
    pub encontradas: usize,
    pub concluidas: usize,
    pub falhas: usize,
}

// Processa um lote de tentativas pendentes e retorna.
//
// Substitui o antigo loop infinito: a cadência agora vem de fora (pg_cron
// chamando POST /process-batch), o que permite o processo escalar a zero entre
// execuções em vez de exigir uma VM ligada 24/7.
//
// Chamadas concorrentes são seguras: fetch_pending usa FOR UPDATE SKIP LOCKED,
// então duas instâncias nunca pegam a mesma tentativa.
pub async fn run_batch(
    db: &PgPool,
    storage_client: &aws_sdk_s3::Client,
    config: &Config,
) -> Result<BatchSummary, sqlx::Error> {
    let rows = attempts::fetch_pending(db, BATCH_SIZE).await?;

    let mut resumo = BatchSummary {
        encontradas: rows.len(),
        ..Default::default()
    };

    for row in rows {
        if process_attempt(db, storage_client, config, row).await {
            resumo.concluidas += 1;
        } else {
            resumo.falhas += 1;
        }
    }

    Ok(resumo)
}

// Retorna true quando a tentativa chegou ao fim do fluxo sem erro.
async fn process_attempt(
    db: &PgPool,
    storage_client: &aws_sdk_s3::Client,
    config: &Config,
    row: attempts::AttemptRow,
) -> bool {
    tracing::info!(attempt_id = %row.id, "iniciando processamento");

    let assets = match attempts::fetch_assets(db, row.id).await {
        Ok(a) => a,
        Err(e) => {
            tracing::error!(attempt_id = %row.id, "erro ao buscar assets: {e}");
            mark_failed_logged(db, &row).await;
            return false;
        }
    };

    if assets.is_empty() {
        tracing::warn!(attempt_id = %row.id, "tentativa sem assets — marcando como falha");
        mark_failed_logged(db, &row).await;
        return false;
    }

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
            return false;
        }

        match storage::download_asset(storage_client, &config.r2_bucket, &asset.object_path).await {
            Ok(bytes) => {
                let byte_count = bytes.len() as i64;
                tracing::info!(
                    attempt_id = %row.id,
                    asset_id = %asset.id,
                    bytes = byte_count,
                    "asset baixado com sucesso"
                );

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
                return false;
            }
        }
    }

    // TODO (Fase P1): chamar OCR → salvar ocr_artifacts → chamar LLM → gravar error_events.
    mark_completed_logged(db, &row).await;
    true
}

async fn mark_completed_logged(db: &PgPool, row: &attempts::AttemptRow) {
    match attempts::mark_completed(db, row.id, row.version).await {
        Ok(true) => tracing::info!(attempt_id = %row.id, "marcado como completed"),
        Ok(false) => {
            tracing::warn!(attempt_id = %row.id, "versão divergiu — outra instância completou antes")
        }
        Err(e) => tracing::error!(attempt_id = %row.id, "erro ao marcar como completed: {e}"),
    }
}

async fn mark_failed_logged(db: &PgPool, row: &attempts::AttemptRow) {
    match attempts::mark_failed(db, row.id, row.version).await {
        Ok(true) => tracing::warn!(attempt_id = %row.id, "marcado como retryable_failed"),
        Ok(false) => {
            tracing::warn!(attempt_id = %row.id, "versão divergiu — outra instância processou")
        }
        Err(e) => tracing::error!(attempt_id = %row.id, "erro ao marcar como failed: {e}"),
    }
}
