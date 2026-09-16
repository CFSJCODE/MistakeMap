use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::Json;

use crate::pipeline;
use crate::AppState;

// POST /process-batch
//
// Processa um lote de tentativas pendentes e responde. Quem define a cadência é
// o pg_cron do Supabase, que chama esta rota periodicamente via pg_net — por
// isso o processo pode escalar a zero entre execuções em vez de exigir uma VM
// ligada 24/7.
//
// A rota é pública na borda (o pg_net não assina requisições com IAM), então a
// autorização é um segredo compartilhado no header X-Cron-Secret.
pub async fn process_batch(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<pipeline::BatchSummary>, StatusCode> {
    autorizar(&headers, &state.config.cron_secret)?;

    let resumo = pipeline::run_batch(&state.db, &state.storage, &state.config)
        .await
        .map_err(|e| {
            tracing::error!("erro ao buscar tentativas pendentes: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    tracing::info!(
        encontradas = resumo.encontradas,
        concluidas = resumo.concluidas,
        falhas = resumo.falhas,
        "lote processado"
    );

    Ok(Json(resumo))
}

fn autorizar(headers: &HeaderMap, esperado: &str) -> Result<(), StatusCode> {
    let recebido = headers
        .get("x-cron-secret")
        .and_then(|v| v.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if iguais_tempo_constante(recebido.as_bytes(), esperado.as_bytes()) {
        Ok(())
    } else {
        tracing::warn!("tentativa de acionar /process-batch com segredo inválido");
        Err(StatusCode::UNAUTHORIZED)
    }
}

// Comparação sem saída antecipada: um `==` comum retorna no primeiro byte
// divergente, e o tempo de resposta revelaria o prefixo correto do segredo.
fn iguais_tempo_constante(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diferenca = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diferenca |= x ^ y;
    }
    diferenca == 0
}
