use chrono::Datelike;
use sqlx::PgPool;

// Limites gratuitos do Cloudflare R2 (por mês calendário).
const CLASS_A_LIMIT: i64 = 1_000_000; // PUT, POST, LIST, COPY
const CLASS_B_LIMIT: i64 = 10_000_000; // GET
const STORAGE_LIMIT_BYTES: i64 = 10 * 1024 * 1024 * 1024; // 10 GB

// Reserva técnica: bloquear quando atingir 95% de qualquer limite.
const THRESHOLD: f64 = 0.95;

pub const CLASS_A_CEILING: i64 = (CLASS_A_LIMIT as f64 * THRESHOLD) as i64; // 950_000
pub const CLASS_B_CEILING: i64 = (CLASS_B_LIMIT as f64 * THRESHOLD) as i64; // 9_500_000
pub const STORAGE_CEILING: i64 = (STORAGE_LIMIT_BYTES as f64 * THRESHOLD) as i64; // ~9.5 GB

#[derive(Debug)]
pub enum QuotaError {
    ClassAExceeded { current: i64, ceiling: i64 },
    ClassBExceeded { current: i64, ceiling: i64 },
    StorageExceeded { current_bytes: i64, ceiling_bytes: i64 },
    Db(sqlx::Error),
}

impl std::fmt::Display for QuotaError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            QuotaError::ClassAExceeded { current, ceiling } => write!(
                f,
                "cota R2 Class A atingida: {current}/{ceiling} ops (limite 95%)"
            ),
            QuotaError::ClassBExceeded { current, ceiling } => write!(
                f,
                "cota R2 Class B atingida: {current}/{ceiling} ops (limite 95%)"
            ),
            QuotaError::StorageExceeded { current_bytes, ceiling_bytes } => write!(
                f,
                "cota R2 storage atingida: {current_bytes}/{ceiling_bytes} bytes (limite 95%)"
            ),
            QuotaError::Db(e) => write!(f, "erro de banco ao verificar cota: {e}"),
        }
    }
}

impl From<sqlx::Error> for QuotaError {
    fn from(e: sqlx::Error) -> Self {
        QuotaError::Db(e)
    }
}

fn current_period() -> String {
    let now = chrono::Utc::now();
    format!("{}-{:02}", now.year(), now.month())
}

// Garante que a linha do mês atual existe.
// Usa INSERT ... ON CONFLICT DO NOTHING para ser seguro com concorrência.
async fn upsert_period(pool: &PgPool, period: &str) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO r2_quota_usage (period) VALUES ($1) ON CONFLICT (period) DO NOTHING")
        .bind(period)
        .execute(pool)
        .await?;
    Ok(())
}

// Verifica se há cota disponível para uma operação Class A (upload).
// Retorna Err se o uso atual >= 95% do limite mensal.
pub async fn check_class_a(pool: &PgPool) -> Result<(), QuotaError> {
    let period = current_period();
    upsert_period(pool, &period).await?;

    let (class_a_ops, storage_bytes): (i64, i64) = sqlx::query_as(
        "SELECT class_a_ops, storage_bytes_estimate FROM r2_quota_usage WHERE period = $1",
    )
    .bind(period.as_str())
    .fetch_one(pool)
    .await?;

    if class_a_ops >= CLASS_A_CEILING {
        return Err(QuotaError::ClassAExceeded {
            current: class_a_ops,
            ceiling: CLASS_A_CEILING,
        });
    }

    if storage_bytes >= STORAGE_CEILING {
        return Err(QuotaError::StorageExceeded {
            current_bytes: storage_bytes,
            ceiling_bytes: STORAGE_CEILING,
        });
    }

    Ok(())
}

// Verifica se há cota disponível para uma operação Class B (download/leitura).
pub async fn check_class_b(pool: &PgPool) -> Result<(), QuotaError> {
    let period = current_period();
    upsert_period(pool, &period).await?;

    let class_b_ops: i64 =
        sqlx::query_scalar("SELECT class_b_ops FROM r2_quota_usage WHERE period = $1")
            .bind(period.as_str())
            .fetch_one(pool)
            .await?;

    if class_b_ops >= CLASS_B_CEILING {
        return Err(QuotaError::ClassBExceeded {
            current: class_b_ops,
            ceiling: CLASS_B_CEILING,
        });
    }

    Ok(())
}

// Incrementa o contador Class A após gerar uma URL presigned de upload.
// Cada URL gerada = 1 PUT futuro pelo Flutter = 1 Class A op.
pub async fn increment_class_a(pool: &PgPool) -> Result<(), sqlx::Error> {
    let period = current_period();
    sqlx::query(
        "UPDATE r2_quota_usage SET class_a_ops = class_a_ops + 1, updated_at = NOW()
         WHERE period = $1",
    )
    .bind(period.as_str())
    .execute(pool)
    .await?;
    Ok(())
}

// Incrementa o contador Class B após um download de asset.
pub async fn increment_class_b(pool: &PgPool) -> Result<(), sqlx::Error> {
    let period = current_period();
    sqlx::query(
        "UPDATE r2_quota_usage SET class_b_ops = class_b_ops + 1, updated_at = NOW()
         WHERE period = $1",
    )
    .bind(period.as_str())
    .execute(pool)
    .await?;
    Ok(())
}

// Acumula bytes no estimador de storage (chamado após download bem-sucedido).
// Nota: o tamanho real é do objeto baixado; para upload usaríamos o Content-Length
// da resposta do R2, mas como usamos presigned URL o Flutter faz o PUT diretamente.
// Portanto, atualizamos o storage só quando sabemos o tamanho (no download).
pub async fn add_storage_bytes(pool: &PgPool, bytes: i64) -> Result<(), sqlx::Error> {
    let period = current_period();
    sqlx::query(
        "UPDATE r2_quota_usage
         SET storage_bytes_estimate = storage_bytes_estimate + $1, updated_at = NOW()
         WHERE period = $2",
    )
    .bind(bytes)
    .bind(period.as_str())
    .execute(pool)
    .await?;
    Ok(())
}

// Retorna o uso atual do mês para logs/monitoramento.
pub async fn current_usage(pool: &PgPool) -> Result<UsageSnapshot, sqlx::Error> {
    let period = current_period();
    upsert_period(pool, &period).await?;

    let (class_a_ops, class_b_ops, storage_bytes): (i64, i64, i64) = sqlx::query_as(
        "SELECT class_a_ops, class_b_ops, storage_bytes_estimate FROM r2_quota_usage WHERE period = $1",
    )
    .bind(period.as_str())
    .fetch_one(pool)
    .await?;

    Ok(UsageSnapshot {
        period,
        class_a_ops,
        class_a_ceiling: CLASS_A_CEILING,
        class_b_ops,
        class_b_ceiling: CLASS_B_CEILING,
        storage_bytes,
        storage_ceiling: STORAGE_CEILING,
    })
}

#[derive(Debug)]
pub struct UsageSnapshot {
    pub period: String,
    pub class_a_ops: i64,
    pub class_a_ceiling: i64,
    pub class_b_ops: i64,
    pub class_b_ceiling: i64,
    pub storage_bytes: i64,
    pub storage_ceiling: i64,
}
