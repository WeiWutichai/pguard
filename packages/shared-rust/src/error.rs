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

    /// A 401 that carries a machine-readable sub-code (e.g. `SESSION_SUPERSEDED`) so
    /// clients branch on `error.code` instead of matching the message text. Same 401
    /// status and the same `{ error: { code, message } }` envelope as
    /// [`AppError::Unauthorized`]; ONLY the `code` string differs (plain `Unauthorized`
    /// keeps `"UNAUTHORIZED"`). `code` is `&'static str` so only a fixed, vetted set of
    /// sub-codes can be emitted. Mirrors [`AppError::ConflictCode`].
    #[error("{message}")]
    UnauthorizedCode { code: &'static str, message: String },

    #[error("{0}")]
    Forbidden(String),

    /// A 403 that carries a machine-readable sub-code (e.g. `NOT_OFFERED_TO_YOU`) so clients
    /// branch on `error.code` and LOCALIZE the copy instead of matching the message text. Same
    /// 403 status and the same `{ error: { code, message } }` envelope as [`AppError::Forbidden`];
    /// ONLY the `code` string differs (plain `Forbidden` keeps `"FORBIDDEN"`). `code` is
    /// `&'static str` so only a fixed, vetted set of sub-codes can be emitted. Mirrors
    /// [`AppError::ConflictCode`].
    #[error("{message}")]
    ForbiddenCode { code: &'static str, message: String },

    #[error("{0}")]
    NotFound(String),

    #[error("{0}")]
    Conflict(String),

    /// A 409 conflict that carries a machine-readable sub-code (e.g. `DUPLICATE_CHECK_IN`)
    /// so clients branch on `error.code` instead of matching the message text. Same 409
    /// status and the same `{ error: { code, message } }` envelope as [`AppError::Conflict`];
    /// ONLY the `code` string differs (plain `Conflict` keeps `"CONFLICT"`). `code` is
    /// `&'static str` so only a fixed, vetted set of sub-codes can be emitted.
    #[error("{message}")]
    ConflictCode { code: &'static str, message: String },

    /// A 400 bad-request that carries a machine-readable sub-code (e.g. `CAPTCHA_INVALID`,
    /// `OTP_COOLDOWN`) so clients branch on `error.code` and LOCALIZE the copy themselves
    /// instead of showing the server's (possibly wrong-language) message. Same 400 status +
    /// the same `{ error: { code, message } }` envelope as [`AppError::BadRequest`]; ONLY the
    /// `code` differs (plain `BadRequest` keeps `"BAD_REQUEST"`). `code` is `&'static str` so
    /// only a fixed, vetted set of sub-codes can be emitted. Mirrors [`AppError::ConflictCode`].
    #[error("{message}")]
    BadRequestCode { code: &'static str, message: String },

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
            // Same 400 as BadRequest; the variant supplies its own machine-readable code.
            AppError::BadRequestCode { code, .. } => (StatusCode::BAD_REQUEST, *code),
            AppError::Unauthorized(_) => (StatusCode::UNAUTHORIZED, "UNAUTHORIZED"),
            // Same 401 as Unauthorized; the variant supplies its own machine-readable code.
            AppError::UnauthorizedCode { code, .. } => (StatusCode::UNAUTHORIZED, *code),
            AppError::Forbidden(_) => (StatusCode::FORBIDDEN, "FORBIDDEN"),
            // Same 403 as Forbidden; the variant supplies its own machine-readable code.
            AppError::ForbiddenCode { code, .. } => (StatusCode::FORBIDDEN, *code),
            AppError::NotFound(_) => (StatusCode::NOT_FOUND, "NOT_FOUND"),
            AppError::Conflict(_) => (StatusCode::CONFLICT, "CONFLICT"),
            // Same 409 as Conflict; the variant supplies its own machine-readable code.
            AppError::ConflictCode { code, .. } => (StatusCode::CONFLICT, *code),
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

    #[tokio::test]
    async fn conflict_keeps_plain_code_in_body() {
        // Backward-compat guard: the plain `Conflict` variant must still serialize the
        // `"CONFLICT"` code (a sub-code must never leak into existing call sites).
        let err = AppError::Conflict("illegal transition".into());
        let body = axum::body::to_bytes(err.into_response().into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["error"]["code"], "CONFLICT");
        assert_eq!(json["error"]["message"], "illegal transition");
    }

    #[tokio::test]
    async fn conflict_code_returns_409_with_custom_code_and_same_envelope() {
        // Same status + envelope SHAPE as Conflict; only the code differs.
        let err = AppError::ConflictCode {
            code: "DUPLICATE_CHECK_IN",
            message: "A check-in for hour 1 already exists".into(),
        };
        let resp = err.into_response();
        assert_eq!(resp.status(), StatusCode::CONFLICT);
        let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["error"]["code"], "DUPLICATE_CHECK_IN");
        assert_eq!(
            json["error"]["message"],
            "A check-in for hour 1 already exists"
        );
        // Envelope shape is exactly `{ error: { code, message } }` — no extra/renamed keys.
        assert!(json["error"].get("code").is_some() && json["error"].get("message").is_some());
        assert_eq!(
            json.as_object().unwrap().len(),
            1,
            "top-level is just `error`"
        );
    }

    #[tokio::test]
    async fn forbidden_code_returns_403_with_custom_code_and_same_envelope() {
        // Same status + envelope SHAPE as Forbidden; only the code differs. Lets clients branch
        // on the sub-code and localize (e.g. booking's directed-offer NOT_OFFERED_TO_YOU).
        let err = AppError::ForbiddenCode {
            code: "NOT_OFFERED_TO_YOU",
            message: "This booking was offered to a specific guard".into(),
        };
        let resp = err.into_response();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["error"]["code"], "NOT_OFFERED_TO_YOU");
        assert_eq!(
            json["error"]["message"],
            "This booking was offered to a specific guard"
        );
        assert_eq!(
            json.as_object().unwrap().len(),
            1,
            "top-level is just `error`"
        );
    }

    #[tokio::test]
    async fn plain_forbidden_keeps_generic_code_in_body() {
        // Backward-compat guard: the plain `Forbidden` variant must still serialize the
        // `"FORBIDDEN"` code (a sub-code must never leak into existing call sites).
        let err = AppError::Forbidden("access denied".into());
        let body = axum::body::to_bytes(err.into_response().into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["error"]["code"], "FORBIDDEN");
    }

    #[tokio::test]
    async fn bad_request_code_returns_400_with_custom_code_and_same_envelope() {
        // Same status + envelope SHAPE as BadRequest; only the code differs. Lets clients
        // branch on the sub-code and localize (e.g. the OTP flow's CAPTCHA_INVALID / OTP_COOLDOWN).
        let err = AppError::BadRequestCode {
            code: "CAPTCHA_INVALID",
            message: "captcha answer wrong".into(),
        };
        let resp = err.into_response();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["error"]["code"], "CAPTCHA_INVALID");
        assert_eq!(json["error"]["message"], "captcha answer wrong");
        assert_eq!(
            json.as_object().unwrap().len(),
            1,
            "top-level is just `error`"
        );
    }

    #[tokio::test]
    async fn unauthorized_code_returns_401_with_custom_code_and_same_envelope() {
        // Same status + envelope SHAPE as Unauthorized; only the code differs.
        let err = AppError::UnauthorizedCode {
            code: "SESSION_SUPERSEDED",
            message: "Signed out because the account was logged in on another device".into(),
        };
        let resp = err.into_response();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["error"]["code"], "SESSION_SUPERSEDED");
        assert_eq!(
            json["error"]["message"],
            "Signed out because the account was logged in on another device"
        );
        // Envelope shape is exactly `{ error: { code, message } }` — no extra/renamed keys.
        assert_eq!(
            json.as_object().unwrap().len(),
            1,
            "top-level is just `error`"
        );
    }

    #[tokio::test]
    async fn plain_unauthorized_keeps_generic_code_in_body() {
        // Backward-compat guard: the plain `Unauthorized` variant must still serialize the
        // `"UNAUTHORIZED"` code (a sub-code must never leak into existing call sites).
        let err = AppError::Unauthorized("invalid token".into());
        let body = axum::body::to_bytes(err.into_response().into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["error"]["code"], "UNAUTHORIZED");
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
