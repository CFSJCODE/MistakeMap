use std::time::Duration;

use aws_sdk_s3::presigning::PresigningConfig;
use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    Json,
};
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// Campos que nos interessam do JWT do Supabase.
// O Supabase inclui muitos outros campos (email, role, etc.) que ignoramos.
#[derive(Debug, Deserialize)]
struct JwtClaims {
    sub: String, // UUID do usuário autenticado — é o user_id que precisamos
}

// Corpo da requisição que o Flutter envia: só a extensão do arquivo.
#[derive(Deserialize)]
pub struct UploadRequest {
    // Extensão sem ponto: "jpg", "png", "pdf"
    extension: String,
}

// Resposta devolvida ao Flutter.
#[derive(Serialize)]
pub struct UploadResponse {
    // URL temporária (15 min) — o Flutter faz PUT aqui com os bytes do arquivo.
    pub url: String,
    // Caminho do objeto dentro do bucket — Flutter salva em attempt_assets.
    pub object_path: String,
}

// Handler: POST /upload-url
// Valida o JWT do Flutter, gera um object_path único e devolve
// uma URL presigned para o Flutter fazer upload direto ao R2.
pub async fn upload_url(
    State(state): State<crate::AppState>,
    headers: HeaderMap,
    Json(body): Json<UploadRequest>,
) -> Result<Json<UploadResponse>, StatusCode> {
    // 1. Extrair o token do header "Authorization: Bearer <token>".
    let token = extract_bearer(&headers)?;

    // 2. Verificar a assinatura ES256 com a chave pública do Supabase.
    //    Se o token for inválido, expirado ou de outro projeto, retorna 401.
    let user_id = validate_jwt(&token, &state.jwt_key)?;

    // 3. Verificar cota R2 Class A antes de qualquer processamento.
    //    Bloqueia quando >= 95% do limite mensal gratuito (950k de 1M ops).
    crate::quota::check_class_a(&state.db).await.map_err(|e| {
        tracing::warn!("upload bloqueado por cota R2: {e}");
        StatusCode::SERVICE_UNAVAILABLE
    })?;

    // 4. Sanitizar a extensão: só formatos permitidos, sem path traversal.
    let ext = sanitize_extension(&body.extension)?;

    // 4. Construir o caminho do objeto no bucket.
    //    Formato: uploads/{user_id}/{uuid}.{ext}
    //    O user_id no caminho permite que políticas futuras verifiquem
    //    propriedade sem precisar consultar o banco.
    let object_path = format!("uploads/{}/{}.{}", user_id, Uuid::new_v4(), ext);

    // 5. Configurar a validade da URL presigned: 15 minutos.
    //    Após esse prazo, qualquer PUT com essa URL é recusado pelo R2.
    let presigning_config = PresigningConfig::expires_in(Duration::from_secs(900))
        .map_err(|e| {
            tracing::error!("erro ao criar presigning config: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // 6. Gerar a URL presigned para PUT no R2.
    //    O SDK assina a URL com as credenciais do worker — o Flutter nunca
    //    vê as credenciais, só a URL temporária resultante.
    let presigned = state
        .storage
        .put_object()
        .bucket(&state.config.r2_bucket)
        .key(&object_path)
        .presigned(presigning_config)
        .await
        .map_err(|e| {
            tracing::error!("erro ao gerar URL presigned: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // Incrementa o contador Class A — cada URL gerada representa 1 PUT futuro.
    if let Err(e) = crate::quota::increment_class_a(&state.db).await {
        tracing::error!("falha ao incrementar cota Class A: {e}");
        // Não bloqueamos o upload por erro de contagem — apenas logamos.
    }

    tracing::info!(
        user_id = %user_id,
        object_path = %object_path,
        "URL presigned gerada com sucesso"
    );

    Ok(Json(UploadResponse {
        url: presigned.uri().to_string(),
        object_path,
    }))
}

// Extrai o token Bearer do header Authorization.
// Retorna 401 se o header não existir ou não tiver o prefixo "Bearer ".
fn extract_bearer(headers: &HeaderMap) -> Result<String, StatusCode> {
    let header = headers
        .get("authorization")
        .ok_or(StatusCode::UNAUTHORIZED)?
        .to_str()
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let token = header
        .strip_prefix("Bearer ")
        .ok_or(StatusCode::UNAUTHORIZED)?;

    Ok(token.to_owned())
}

// Verifica a assinatura ES256 do JWT usando a chave pública do Supabase.
// Retorna o user_id (claim `sub`) se tudo estiver correto.
//
// Por que ES256 e não HS256?
// O Supabase migrou para chaves ECC (P-256) assimétricas. Com ES256, o
// worker só precisa da chave PÚBLICA — nunca do segredo de assinatura.
// Isso é mais seguro: mesmo que o worker seja comprometido, o atacante
// não consegue forjar tokens.
fn validate_jwt(token: &str, key: &DecodingKey) -> Result<String, StatusCode> {
    let mut validation = Validation::new(Algorithm::ES256);
    // O Supabase emite tokens com audience "authenticated" para usuários logados.
    validation.set_audience(&["authenticated"]);

    let token_data = decode::<JwtClaims>(token, key, &validation).map_err(|e| {
        tracing::warn!("JWT inválido ou expirado: {e}");
        StatusCode::UNAUTHORIZED
    })?;

    Ok(token_data.claims.sub)
}

// Garante que a extensão é um formato permitido.
// Retorna 400 para qualquer coisa fora da lista — inclui tentativas de
// injeção como "../etc/passwd" ou "php".
fn sanitize_extension(ext: &str) -> Result<String, StatusCode> {
    let ext = ext.trim().to_lowercase();

    const ALLOWED: &[&str] = &["jpg", "jpeg", "png", "webp", "pdf"];

    if ALLOWED.contains(&ext.as_str()) {
        Ok(ext)
    } else {
        tracing::warn!("extensão rejeitada: '{ext}'");
        Err(StatusCode::BAD_REQUEST)
    }
}
