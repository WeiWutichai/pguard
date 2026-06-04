//! API layer — thin Axum transport handlers. No business logic beyond orchestration of
//! `domain` (pure decisions) + `repo` (DB) + JWT/cookie issuance.

use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, HeaderValue};
use axum::response::IntoResponse;
use axum::Json;
use redis::AsyncCommands;
use uuid::Uuid;

use shared::auth::{
    build_clear_cookie, build_cookie, decode_jwt_with_key, encode_jwt_with_key,
    extract_cookie_value, AuthUser, ACCESS_TOKEN_COOKIE, REFRESH_TOKEN_COOKIE,
};
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::domain::rotation::{decide, RotationDecision};
use crate::domain::token;
use crate::models::{LoginRequest, MeResponse, RefreshRequest, TokenPair};
use crate::repo;
use crate::state::{AppState, RevokeAllDeps};

/// Refresh-cookie lifetime (seconds) — mirrors the 7-day refresh-token TTL in `repo`.
const REFRESH_COOKIE_MAX_AGE_SECS: i64 = 7 * 24 * 60 * 60;
/// Refresh cookie is scoped to the auth paths only (it is never needed elsewhere).
const REFRESH_COOKIE_PATH: &str = "/auth";

/// Build the response that carries the token pair both in the JSON body (mobile/API) and
/// as httpOnly Secure SameSite=Lax cookies (web).
fn token_response(pair: TokenPair, access_max_age_secs: i64) -> impl IntoResponse {
    let mut headers = HeaderMap::new();
    append_cookie(
        &mut headers,
        &build_cookie(
            ACCESS_TOKEN_COOKIE,
            &pair.access_token,
            access_max_age_secs,
            "/",
        ),
    );
    append_cookie(
        &mut headers,
        &build_cookie(
            REFRESH_TOKEN_COOKIE,
            &pair.refresh_token,
            REFRESH_COOKIE_MAX_AGE_SECS,
            REFRESH_COOKIE_PATH,
        ),
    );
    (headers, Json(ApiResponse::success(pair)))
}

fn append_cookie(headers: &mut HeaderMap, cookie: &str) {
    if let Ok(value) = HeaderValue::from_str(cookie) {
        headers.append(header::SET_COOKIE, value);
    }
}

// ----- POST /auth/login -----

pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<impl IntoResponse, AppError> {
    if req.identifier.trim().is_empty() || req.password.is_empty() {
        // Generic 401 — never reveal which field was the problem.
        return Err(AppError::Unauthorized("Invalid credentials".to_string()));
    }

    let user = repo::verify_credentials(&state.db, req.identifier.trim(), &req.password).await?;

    let (access_token, _jti) = encode_jwt_with_key(
        user.id,
        &user.role,
        &state.jwt_config.encoding_key,
        state.jwt_config.expiry_minutes,
    )?;
    let refresh_token = repo::create_refresh_family(&state.db, user.id).await?;

    let pair = TokenPair {
        access_token,
        refresh_token,
        expires_in: state.jwt_config.expiry_minutes * 60,
        token_type: "Bearer",
    };
    Ok(token_response(pair, state.jwt_config.expiry_minutes * 60))
}

// ----- POST /auth/refresh -----

pub async fn refresh(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Option<Json<RefreshRequest>>,
) -> Result<impl IntoResponse, AppError> {
    // Accept the refresh token from the body (mobile/API) or the cookie (web sends an
    // empty body and relies on the httpOnly cookie).
    let presented = body
        .map(|Json(b)| b.refresh_token)
        .filter(|t| !t.is_empty())
        .or_else(|| {
            headers
                .get(header::COOKIE)
                .and_then(|v| v.to_str().ok())
                .and_then(|c| extract_cookie_value(c, REFRESH_TOKEN_COOKIE))
                .map(|t| t.to_string())
        })
        .ok_or_else(|| AppError::Unauthorized("Missing refresh token".to_string()))?;

    let generic_401 = || AppError::Unauthorized("Invalid refresh token".to_string());

    let (rotation_id, secret) = token::parse(&presented).ok_or_else(generic_401)?;

    let located = repo::find_refresh_by_rotation(&state.db, rotation_id)
        .await?
        .ok_or_else(generic_401)?;

    // Constant-time secret check before trusting the row at all.
    if !located.secret_matches(secret).await? {
        return Err(generic_401());
    }

    match decide(&located.stored, chrono::Utc::now()) {
        RotationDecision::ReuseDetected => {
            // Token reuse (RFC 6749 §6): a previously-rotated token was replayed. Kill the
            // entire family and reject. (alert hook is a followup — see SLICE notes.)
            tracing::warn!(
                user_id = %located.user_id,
                family_id = %located.family_id,
                "refresh-token reuse detected — revoking family"
            );
            repo::revoke_family(&state.db, located.family_id).await?;
            Err(generic_401())
        }
        RotationDecision::Expired => Err(generic_401()),
        RotationDecision::Rotate => {
            // Re-read the user's current role + revocation version for the new access token.
            let meta = repo::user_auth_meta(&state.db, located.user_id)
                .await?
                .ok_or_else(generic_401)?;

            let refresh_token =
                repo::rotate(&state.db, located.user_id, located.family_id, rotation_id).await?;
            let (access_token, _jti) = encode_jwt_with_key(
                meta.id,
                &meta.role,
                &state.jwt_config.encoding_key,
                state.jwt_config.expiry_minutes,
            )?;

            let pair = TokenPair {
                access_token,
                refresh_token,
                expires_in: state.jwt_config.expiry_minutes * 60,
                token_type: "Bearer",
            };
            Ok(token_response(pair, state.jwt_config.expiry_minutes * 60))
        }
    }
}

// ----- POST /auth/logout -----

pub async fn logout(
    State(state): State<AppState>,
    user: AuthUser,
    headers: HeaderMap,
    body: Option<Json<RefreshRequest>>,
) -> Result<impl IntoResponse, AppError> {
    // 1) Blocklist the presented access-token jti so it can't be reused before expiry.
    if let Some(jti_ttl) = access_jti_and_ttl(&state, &headers) {
        let (jti, ttl_secs) = jti_ttl;
        let mut redis = state.redis_conn.clone();
        let key = format!("revoked_jti:{jti}");
        // Best-effort: a Redis hiccup must not fail logout (token still expires naturally).
        let _: Result<(), redis::RedisError> =
            redis.set_ex(&key, user.user_id.to_string(), ttl_secs).await;
    }

    // 2) Revoke the current refresh family (if a refresh token was supplied).
    let presented = body
        .map(|Json(b)| b.refresh_token)
        .filter(|t| !t.is_empty())
        .or_else(|| {
            headers
                .get(header::COOKIE)
                .and_then(|v| v.to_str().ok())
                .and_then(|c| extract_cookie_value(c, REFRESH_TOKEN_COOKIE))
                .map(|t| t.to_string())
        });
    if let Some(presented) = presented {
        if let Some((rotation_id, _)) = token::parse(&presented) {
            if let Some(located) = repo::find_refresh_by_rotation(&state.db, rotation_id).await? {
                repo::revoke_family(&state.db, located.family_id).await?;
            }
        }
    }

    // 3) Clear the cookies.
    let mut out = HeaderMap::new();
    append_cookie(&mut out, &build_clear_cookie(ACCESS_TOKEN_COOKIE, "/"));
    append_cookie(
        &mut out,
        &build_clear_cookie(REFRESH_TOKEN_COOKIE, REFRESH_COOKIE_PATH),
    );
    Ok((out, Json(ApiResponse::success(()))))
}

/// Pull the access token from the request, decode it, and return `(jti, remaining_ttl)`
/// so we blocklist it for exactly its remaining lifetime. Returns `None` if absent or
/// undecodable (nothing to blocklist).
fn access_jti_and_ttl(state: &AppState, headers: &HeaderMap) -> Option<(String, u64)> {
    let token = headers
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer ").map(|t| t.to_string()))
        .or_else(|| {
            headers
                .get(header::COOKIE)
                .and_then(|v| v.to_str().ok())
                .and_then(|c| extract_cookie_value(c, ACCESS_TOKEN_COOKIE))
                .map(|t| t.to_string())
        })?;
    let claims = decode_jwt_with_key(&token, &state.jwt_config.decoding_key).ok()?;
    let ttl = (claims.exp - chrono::Utc::now().timestamp()).max(1) as u64;
    Some((claims.jti, ttl))
}

// ----- GET /auth/me -----

pub async fn me(user: AuthUser) -> Json<ApiResponse<MeResponse>> {
    Json(ApiResponse::success(MeResponse {
        user_id: user.user_id,
        role: user.role,
    }))
}

// ----- POST /internal/users/{id}/revoke-all -----

/// Force-revoke-all for a user (service-to-service). **v2:** requires a valid service-JWT
/// (`ServiceCaller`). Bumps the user's `token_revocation_version` and revokes every
/// outstanding refresh family. Generic over [`RevokeAllDeps`] so the service-JWT guard is
/// testable in isolation (mirrors notification's `internal_push`).
pub async fn internal_revoke_all<S: RevokeAllDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<()>>, AppError> {
    tracing::info!(caller = %caller.service, %user_id, "internal revoke-all");
    repo::revoke_all(state.db(), user_id).await?;
    Ok(Json(ApiResponse::success(())))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::post;
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::service_jwt::{encode_service_jwt, HasServiceJwt};
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "service-secret-at-least-64-characters-long-for-internal-hs256-test!!";

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
    }

    impl HasServiceJwt for TestDeps {
        fn service_decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
    }
    impl RevokeAllDeps for TestDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    fn router() -> Router {
        // Lazy pool to a closed port — never connects unless a handler queries. Rejected
        // requests short-circuit at the ServiceCaller guard, so the DB is never touched.
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db,
        };
        Router::new()
            .route(
                "/internal/users/{id}/revoke-all",
                post(internal_revoke_all::<TestDeps>),
            )
            .with_state(deps)
    }

    const URI: &str = "/internal/users/00000000-0000-0000-0000-000000000001/revoke-all";

    #[tokio::test]
    async fn revoke_all_rejects_missing_token() {
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(URI)
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn revoke_all_rejects_invalid_token() {
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(URI)
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn revoke_all_accepts_valid_service_token() {
        // A valid service-JWT must pass the guard. The handler then tries to query the
        // (unreachable) DB, so the response is NOT 401 — proving auth was accepted.
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let tok = encode_service_jwt("booking", &ek, 60).unwrap();
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(URI)
                    .header("authorization", format!("Bearer {tok}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_ne!(
            res.status(),
            StatusCode::UNAUTHORIZED,
            "valid service token must pass the guard"
        );
    }
}
