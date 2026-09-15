use aws_sdk_s3::Client;
use aws_sdk_s3::config::{Credentials, Region};
use bytes::Bytes;

use crate::config::Config;

pub fn build_client(cfg: &Config) -> Client {
    let credentials = Credentials::new(
        &cfg.r2_access_key_id,
        &cfg.r2_secret_access_key,
        None,
        None,
        "mistakemap-worker",
    );

    let s3_config = aws_sdk_s3::Config::builder()
        .endpoint_url(&cfg.r2_endpoint)
        .region(Region::new("auto"))
        .credentials_provider(credentials)
        .behavior_version_latest()
        .force_path_style(true)
        .build();

    Client::from_conf(s3_config)
}

pub async fn ping(client: &Client, bucket: &str) -> Result<(), aws_sdk_s3::Error> {
    client.head_bucket().bucket(bucket).send().await?;
    Ok(())
}

// Baixa um objeto do R2 e retorna seus bytes em memória.
//
// `object_path` é a chave S3 do objeto — o valor gravado em
// attempt_assets.object_path (ex: "uploads/<uuid>/foto.jpg").
// Não é uma URL, só o caminho dentro do bucket.
//
// Por que collect() em vez de stream incremental?
// Para o MVP, os assets são fotos/PDFs de tamanho razoável.
// collect() simplifica o código sem custo prático. Se no futuro
// precisarmos de streaming real (ex: vídeos), substituímos aqui
// sem mudar quem chama.
pub async fn download_asset(
    client: &Client,
    bucket: &str,
    object_path: &str,
) -> Result<Bytes, StorageError> {
    let output = client
        .get_object()
        .bucket(bucket)
        .key(object_path)
        .send()
        .await
        .map_err(|e| StorageError::GetObject {
            path: object_path.to_owned(),
            source: Box::new(e),
        })?;

    let bytes = output
        .body
        .collect()
        .await
        .map_err(|e| StorageError::ReadBody {
            path: object_path.to_owned(),
            source: Box::new(e),
        })?
        .into_bytes();

    Ok(bytes)
}

// Erro tipado para operações de storage.
//
// Por que não usar aws_sdk_s3::Error diretamente?
// Porque misturar "falha ao buscar" com "falha ao ler body" no mesmo tipo
// genérico torna o match no chamador mais difícil. Com variantes nomeadas,
// o main.rs pode logar mensagens distintas para cada caso.
#[derive(Debug)]
pub enum StorageError {
    GetObject {
        path: String,
        source: Box<dyn std::error::Error + Send + Sync>,
    },
    ReadBody {
        path: String,
        source: Box<dyn std::error::Error + Send + Sync>,
    },
}

impl std::fmt::Display for StorageError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StorageError::GetObject { path, source } => {
                write!(f, "falha ao buscar objeto '{path}' no R2: {source}")
            }
            StorageError::ReadBody { path, source } => {
                write!(f, "falha ao ler body do objeto '{path}': {source}")
            }
        }
    }
}

impl std::error::Error for StorageError {}
