//! Unified application error type + JSON error body. Ported from v1.
//!
//! Database/Redis errors are logged with detail but returned to clients as a
//! generic message (no internal leakage).

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use utoipa::ToSchema;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("{0}")]
    BadRequest(String),

    #[error("{0}")]
    Unauthorized(String),

    #[error("{0}")]
    Forbidden(String),

    #[error("{0}")]
    NotFound(String),

    #[error("{0}")]
    Conflict(String),

    #[error("{0}")]
    Internal(String),

    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("redis error: {0}")]
    Redis(#[from] redis::RedisError),
}

#[derive(Serialize, ToSchema)]
pub struct ErrorBody {
    pub error: ErrorDetail,
}

#[derive(Serialize, ToSchema)]
pub struct ErrorDetail {
    /// Error code (e.g., "BAD_REQUEST", "UNAUTHORIZED", "NOT_FOUND").
    pub code: String,
    /// Human-readable error message.
    pub message: String,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code) = match &self {
            AppError::BadRequest(_) => (StatusCode::BAD_REQUEST, "BAD_REQUEST"),
            AppError::Unauthorized(_) => (StatusCode::UNAUTHORIZED, "UNAUTHORIZED"),
            AppError::Forbidden(_) => (StatusCode::FORBIDDEN, "FORBIDDEN"),
            AppError::NotFound(_) => (StatusCode::NOT_FOUND, "NOT_FOUND"),
            AppError::Conflict(_) => (StatusCode::CONFLICT, "CONFLICT"),
            AppError::Internal(_) => (StatusCode::INTERNAL_SERVER_ERROR, "INTERNAL_ERROR"),
            AppError::Database(e) => {
                tracing::error!("Database error: {e}");
                (StatusCode::INTERNAL_SERVER_ERROR, "DATABASE_ERROR")
            }
            AppError::Redis(e) => {
                tracing::error!("Redis error: {e}");
                (StatusCode::INTERNAL_SERVER_ERROR, "CACHE_ERROR")
            }
        };

        let message = match &self {
            AppError::Database(_) | AppError::Redis(_) => "An internal error occurred".to_string(),
            other => other.to_string(),
        };

        let body = ErrorBody {
            error: ErrorDetail {
                code: code.to_string(),
                message,
            },
        };

        (status, axum::Json(body)).into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bad_request_returns_400() {
        let err = AppError::BadRequest("missing field".into());
        assert_eq!(err.into_response().status(), StatusCode::BAD_REQUEST);
    }

    #[test]
    fn unauthorized_returns_401() {
        let err = AppError::Unauthorized("invalid token".into());
        assert_eq!(err.into_response().status(), StatusCode::UNAUTHORIZED);
    }

    #[test]
    fn forbidden_returns_403() {
        let err = AppError::Forbidden("access denied".into());
        assert_eq!(err.into_response().status(), StatusCode::FORBIDDEN);
    }

    #[test]
    fn not_found_returns_404() {
        let err = AppError::NotFound("no such user".into());
        assert_eq!(err.into_response().status(), StatusCode::NOT_FOUND);
    }

    #[test]
    fn conflict_returns_409() {
        let err = AppError::Conflict("email already exists".into());
        assert_eq!(err.into_response().status(), StatusCode::CONFLICT);
    }

    #[test]
    fn internal_returns_500() {
        let err = AppError::Internal("something broke".into());
        assert_eq!(
            err.into_response().status(),
            StatusCode::INTERNAL_SERVER_ERROR
        );
    }

    #[tokio::test]
    async fn error_response_body_is_json_with_code_and_message() {
        let err = AppError::BadRequest("name is required".into());
        let response = err.into_response();
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["error"]["code"], "BAD_REQUEST");
        assert_eq!(json["error"]["message"], "name is required");
    }

    #[tokio::test]
    async fn database_error_hides_internal_details() {
        let err = AppError::Database(sqlx::Error::PoolTimedOut);
        let response = err.into_response();
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["error"]["code"], "DATABASE_ERROR");
        assert_eq!(json["error"]["message"], "An internal error occurred");
    }

    #[test]
    fn display_trait_shows_message() {
        let err = AppError::BadRequest("test message".into());
        assert_eq!(err.to_string(), "test message");
    }
}
