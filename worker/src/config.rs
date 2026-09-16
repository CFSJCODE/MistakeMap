use std::env;

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub r2_account_id: String,
    pub r2_endpoint: String,
    pub r2_bucket: String,
    pub r2_access_key_id: String,
    pub r2_secret_access_key: String,
    pub port: u16,
    // URL base do projeto Supabase — usada para buscar as chaves públicas JWT (JWKS).
    // Formato: https://<project-ref>.supabase.co
    pub supabase_url: String,
    // Segredo compartilhado que autoriza POST /process-batch.
    // A rota e publica na borda porque o pg_net nao assina com IAM.
    pub cron_secret: String,
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let get = |key: &str| -> Result<String, String> {
            env::var(key).map_err(|_| format!("variável de ambiente ausente: {key}"))
        };

        Ok(Self {
            database_url: get("DATABASE_URL")?,
            r2_account_id: get("CLOUDFLARE_ACCOUNT_ID")?,
            r2_endpoint: get("CLOUDFLARE_R2_S3_ENDPOINT")?,
            r2_bucket: get("CLOUDFLARE_R2_BUCKET")?,
            r2_access_key_id: get("CLOUDFLARE_R2_ACCESS_KEY_ID")?,
            r2_secret_access_key: get("CLOUDFLARE_R2_SECRET_ACCESS_KEY")?,
            supabase_url: get("SUPABASE_URL")?,
            cron_secret: get("WORKER_CRON_SECRET")?,
            port: env::var("PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(8080),
        })
    }
}
