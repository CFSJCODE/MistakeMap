use sqlx::PgPool;
use uuid::Uuid;

// Representa um asset (foto, PDF) associado a uma tentativa.
#[derive(Debug, sqlx::FromRow)]
pub struct AssetRow {
    pub id: Uuid,
    pub object_path: String,
}

// Representa uma tentativa do aluno da forma que o worker precisa enxergar.
// Só mapeamos as colunas que o worker efetivamente usa — colunas extras no
// banco (solution_text, answer, etc.) são ignoradas sem erro pelo sqlx.
#[derive(Debug, sqlx::FromRow)]
pub struct AttemptRow {
    pub id: Uuid,
    pub status: String,
    pub version: i32,
}

// Busca e trava até `limit` tentativas com status 'pending', promovendo-as
// para 'queued' atomicamente.
//
// Por que UPDATE ... RETURNING em vez de SELECT depois UPDATE?
// Porque SELECT + UPDATE separados têm race condition: dois workers poderiam
// pegar a mesma linha entre o SELECT e o UPDATE. A query abaixo é atômica:
// o FOR UPDATE SKIP LOCKED garante que cada worker pega linhas distintas sem
// bloquear uns aos outros.
pub async fn fetch_pending(pool: &PgPool, limit: i64) -> Result<Vec<AttemptRow>, sqlx::Error> {
    sqlx::query_as::<_, AttemptRow>(
        r#"
        UPDATE public.attempts
        SET
            status  = 'queued',
            version = version + 1
        WHERE id IN (
            SELECT id
            FROM public.attempts
            WHERE status = 'pending'
            ORDER BY attempted_at
            LIMIT $1
            FOR UPDATE SKIP LOCKED
        )
        RETURNING id, status, version
        "#,
    )
    .bind(limit)
    .fetch_all(pool)
    .await
}

// Retorna os assets (arquivos no R2) de uma tentativa específica.
// O worker usa object_path para baixar cada arquivo via storage::download_asset.
pub async fn fetch_assets(
    pool: &PgPool,
    attempt_id: Uuid,
) -> Result<Vec<AssetRow>, sqlx::Error> {
    sqlx::query_as::<_, AssetRow>(
        r#"
        SELECT id, object_path
        FROM public.attempt_assets
        WHERE attempt_id = $1
        ORDER BY created_at
        "#,
    )
    .bind(attempt_id)
    .fetch_all(pool)
    .await
}

// Marca uma tentativa como 'completed'.
//
// Mesmo contrato de mark_failed: usa expected_version para detectar writes
// concorrentes. Ok(true) = sucesso, Ok(false) = outra instância ganhou a corrida.
pub async fn mark_completed(
    pool: &PgPool,
    attempt_id: Uuid,
    expected_version: i32,
) -> Result<bool, sqlx::Error> {
    let rows_affected = sqlx::query(
        r#"
        UPDATE public.attempts
        SET
            status  = 'completed',
            version = version + 1
        WHERE id = $1
          AND version = $2
        "#,
    )
    .bind(attempt_id)
    .bind(expected_version)
    .execute(pool)
    .await?
    .rows_affected();

    Ok(rows_affected == 1)
}

// Marca uma tentativa como 'retryable_failed' usando o número de versão lido
// anteriormente. Se outra process alterou a linha (version divergiu), o UPDATE
// afeta 0 linhas — retornamos Ok(false) para o chamador logar/alertar.
pub async fn mark_failed(
    pool: &PgPool,
    attempt_id: Uuid,
    expected_version: i32,
) -> Result<bool, sqlx::Error> {
    let rows_affected = sqlx::query(
        r#"
        UPDATE public.attempts
        SET
            status  = 'retryable_failed',
            version = version + 1
        WHERE id = $1
          AND version = $2
        "#,
    )
    .bind(attempt_id)
    .bind(expected_version)
    .execute(pool)
    .await?
    .rows_affected();

    Ok(rows_affected == 1)
}
