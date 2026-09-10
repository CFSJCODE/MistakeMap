use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use serde_json::json;

use crate::AppState;

pub async fn health(State(state): State<AppState>) -> (StatusCode, Json<serde_json::Value>) {
    let db_ok = crate::db::ping(&state.db).await.is_ok();
    let r2_ok = crate::storage::ping(&state.storage, &state.config.r2_bucket)
        .await
        .is_ok();

    let status = if db_ok && r2_ok {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };

    (
        status,
        Json(json!({
            "database": if db_ok { "ok" } else { "error" },
            "r2": if r2_ok { "ok" } else { "error" },
            "bucket": state.config.r2_bucket,
        })),
    )
}
