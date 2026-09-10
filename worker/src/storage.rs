use aws_sdk_s3::Client;
use aws_sdk_s3::config::{Credentials, Region};

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
