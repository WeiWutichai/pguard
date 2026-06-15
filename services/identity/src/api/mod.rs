//! API layer — thin Axum transport handlers. No business logic beyond orchestration of
//! `domain` (pure decisions) + `repo` (DB) + JWT/cookie issuance.

use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::IntoResponse;
use axum::Json;
use redis::AsyncCommands;
use uuid::Uuid;

use shared::auth::{
    build_clear_cookie, build_cookie, decode_jwt_with_key, decode_phone_verify_token,
    encode_jwt_with_key, encode_profile_token, extract_cookie_value, AuthUser, ACCESS_TOKEN_COOKIE,
    REFRESH_TOKEN_COOKIE,
};
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::domain::rotation::{decide, RotationDecision};
use crate::domain::{registration, token};
use crate::models::{
    LoginRequest, MeResponse, RefreshRequest, RegisterRequest, RegisterResult, TokenPair,
};
use crate::repo;
use crate::state::{AppState, RegisterDeps, RevokeAllDeps};

/// Refresh-cookie lifetime (seconds) — mirrors the 7-day refresh-token TTL in `repo`.
const REFRESH_COOKIE_MAX_AGE_SECS: i64 = 7 * 24 * 60 * 60;
/// Refresh cookie is scoped to the auth paths only (it is never needed elsewhere).
const REFRESH_COOKIE_PATH: &str = "/auth";
/// Single-use profile-token lifetime (minutes) — short window to submit the onboarding
/// profile right after registering.
const PROFILE_TOKEN_TTL_MINUTES: i64 = 15;
/// Clock-skew buffer added to the profile-token jti's Redis TTL beyond the JWT exp, so the
/// single-use marker never expires a hair before the token it guards.
const PROFILE_JTI_SKEW_BUFFER_SECS: i64 = 30;

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

// `skip_all`: never log the identifier (PII) or the password.
#[tracing::instrument(skip_all)]
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
        user.token_revocation_version as i64,
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

// ----- POST /auth/register -----

/// Create an account from a verified phone + chosen role. Returns **202 Accepted** with a
/// single-use `profile_token` and NO access/refresh tokens — the account is `pending` and
/// cannot authenticate until approved (login gates on `approval_status`).
///
/// Order is deliberate: cheap input validation (role/pin shape) runs FIRST so a bad request
/// (e.g. self-assigning `admin`) is rejected WITHOUT burning the user's single-use OTP
/// token; only then is the phone-verify token verified and atomically consumed (GETDEL).
///
/// `skip_all`: never log the tokens, the pin_hash, or the phone (PII).
#[tracing::instrument(skip_all)]
pub async fn register<S: RegisterDeps>(
    State(state): State<S>,
    Json(req): Json<RegisterRequest>,
) -> Result<impl IntoResponse, AppError> {
    // 1) Validate inputs BEFORE any side effect (don't consume the OTP token on bad input).
    let role = registration::validate_registration_role(&req.role)?;
    registration::validate_pin_hash(&req.pin_hash)?;

    // 2) Verify the phone-verified token (signature + purpose + expiry). The phone comes
    //    from the token, never from the body.
    let (phone, jti) =
        decode_phone_verify_token(&req.phone_verified_token, state.jwt_decoding_key())?;

    // 3) Defensive re-validation/normalization of the token's phone (otp validated it at
    //    issuance; identity never trusts a value off the wire). Done BEFORE the GETDEL so a
    //    malformed-phone token is rejected WITHOUT burning the user's single-use OTP token.
    let phone = registration::validate_thai_phone(&phone)?;

    // 4) Single-use: atomically claim the jti (GETDEL). A reused/expired/forged token has no
    //    live "valid" marker → reject. This runs before the UPSERT so concurrent registers
    //    with the same token cannot both proceed.
    let mut redis = state.redis();
    let jti_status: Option<String> = redis::cmd("GETDEL")
        .arg(format!("phone_verify_jti:{jti}"))
        .query_async(&mut redis)
        .await?;
    if jti_status.as_deref() != Some("valid") {
        return Err(AppError::BadRequest(
            "Phone verification token is invalid, expired, or already used".to_string(),
        ));
    }

    // 5) UPSERT the pending account (Argon2 of pin_hash happens inside repo via spawn_blocking).
    //    A non-pending phone → Conflict ("log in instead").
    let user_id =
        repo::upsert_pending_user(state.db(), &phone, &role.to_string(), &req.pin_hash).await?;

    // 6) Mint the single-use profile_token for this role's onboarding route + record its jti
    //    so profile can GETDEL it once. (admin has no profile route — but it was already
    //    rejected at step 1, so this never errors in practice.)
    let purpose = registration::profile_purpose_for_role(&role)?;
    let (profile_token, profile_jti) = encode_profile_token(
        user_id,
        purpose,
        state.jwt_encoding_key(),
        PROFILE_TOKEN_TTL_MINUTES,
    )?;
    let ttl_secs = (PROFILE_TOKEN_TTL_MINUTES * 60 + PROFILE_JTI_SKEW_BUFFER_SECS) as u64;
    redis
        .set_ex::<_, _, ()>(format!("profile_jti:{profile_jti}"), "valid", ttl_secs)
        .await?;

    tracing::info!(%user_id, role = %role, "account registered (pending approval)");

    // 7) 202 Accepted — NO tokens, NO session row. The client submits its profile with the
    //    profile_token, then waits for approval before it can log in.
    Ok((
        StatusCode::ACCEPTED,
        Json(ApiResponse::success(RegisterResult {
            user_id,
            profile_token,
        })),
    ))
}

// ----- POST /auth/refresh -----

#[tracing::instrument(skip_all)]
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
        // Absolute rotation ceiling (RFC-6749-aligned hardening) — now decided in
        // `domain::rotation::decide` (family older than FAMILY_MAX_DAYS). Benign: force re-login,
        // no family kill. Generic 401, same as expiry.
        RotationDecision::CeilingExceeded => Err(generic_401()),
        RotationDecision::Rotate => {
            // Re-read the user's current role + revocation version for the new access token.
            let meta = repo::user_auth_meta(&state.db, located.user_id)
                .await?
                .ok_or_else(generic_401)?;

            let Some(refresh_token) =
                repo::rotate(&state.db, located.user_id, located.family_id, rotation_id).await?
            else {
                // A concurrent refresh of this exact token already rotated the row (double-spend
                // race). Minting a second successor would create two live chains from one token,
                // so reject this loser. We do NOT kill the family: the winner holds a brand-new
                // token in it, and a benign client double-fire must not log itself out.
                tracing::warn!(
                    user_id = %located.user_id,
                    "concurrent refresh rotation lost the race — rejecting (no second chain minted)"
                );
                return Err(generic_401());
            };
            let (access_token, _jti) = encode_jwt_with_key(
                meta.id,
                &meta.role,
                meta.token_revocation_version as i64,
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

#[tracing::instrument(skip_all, fields(user = %user.user_id))]
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
        // Best-effort: a Redis hiccup must not fail logout (token still expires naturally),
        // but log it so the (small) gap is observable.
        if let Err(e) = redis
            .set_ex::<_, _, ()>(&key, user.user_id.to_string(), ttl_secs)
            .await
        {
            tracing::warn!("failed to blocklist access jti on logout: {e}");
        }
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

#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn me(user: AuthUser) -> Json<ApiResponse<MeResponse>> {
    Json(ApiResponse::success(MeResponse {
        user_id: user.user_id,
        role: user.role,
    }))
}

// ----- DELETE /auth/me (PDPA §33 — right to erasure) -----

/// Erase the authenticated user's own account: soft-delete + PII redaction, force-revoke
/// every token, and clear the auth cookies. Afterwards the account cannot authenticate
/// (deactivated + PII redacted), and outstanding access tokens are rejected at once via the
/// Redis `trv` marker. The redacted row is retained as minimal deletion audit (PDPA §33).
#[tracing::instrument(skip_all, fields(user_id = %user.user_id))]
pub async fn delete_me(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let new_version = repo::soft_delete_and_redact(&state.db, user.user_id).await?;

    // Reject every outstanding access token immediately (force-revoke-all marker).
    let mut redis = state.redis_conn.clone();
    crate::state::mark_user_revoked(&mut redis, user.user_id, new_version).await;

    // Clear the auth cookies on the way out (web).
    let mut headers = HeaderMap::new();
    append_cookie(&mut headers, &build_clear_cookie(ACCESS_TOKEN_COOKIE, "/"));
    append_cookie(
        &mut headers,
        &build_clear_cookie(REFRESH_TOKEN_COOKIE, REFRESH_COOKIE_PATH),
    );
    Ok((
        headers,
        Json(ApiResponse::success(serde_json::json!({ "deleted": true }))),
    ))
}

// ----- GET /me/data-export (PDPA §19 access / §32 portability) -----

/// Aggregate the authenticated user's data from every owning service (identity own fields +
/// profile + bookings + payments + reviews) into one machine-readable JSON envelope.
/// Best-effort: a downstream that's unavailable is marked `"error"` in `_meta.sections`
/// rather than failing the whole export, so the user still receives what's retrievable.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn data_export(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let user_data = repo::export_user(&state.db, user.user_id).await?;
    let sections = state.export_client.collect(user.user_id).await;

    let mut envelope = serde_json::Map::new();
    envelope.insert("user".to_string(), user_data);
    let mut meta_sections = serde_json::Map::new();
    for s in sections {
        meta_sections.insert(
            s.name.to_string(),
            serde_json::Value::String(s.status.to_string()),
        );
        envelope.insert(s.name.to_string(), s.data);
    }
    envelope.insert(
        "_meta".to_string(),
        serde_json::json!({
            "generated_at": chrono::Utc::now(),
            "sections": serde_json::Value::Object(meta_sections),
        }),
    );
    Ok(Json(ApiResponse::success(serde_json::Value::Object(
        envelope,
    ))))
}

// ----- POST /auth/revoke-all (self-serve "sign out everywhere") -----

/// Force-revoke ALL of the caller's own sessions ("sign out everywhere" on the admin profile
/// screen). Bumps the user's `token_revocation_version` + revokes every refresh family (so every
/// other device's tokens are rejected at once via the Redis `trv` marker), then clears THIS
/// browser's auth cookies so the current session ends too. Mirrors `delete_me`'s revoke path,
/// without the soft-delete/PII-redaction — the account stays active, just re-auth-required.
#[tracing::instrument(skip_all, fields(user_id = %user.user_id))]
pub async fn revoke_all_sessions(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let version = repo::revoke_all(&state.db, user.user_id).await?;
    let mut redis = state.redis_conn.clone();
    crate::state::mark_user_revoked(&mut redis, user.user_id, version).await;

    let mut headers = HeaderMap::new();
    append_cookie(&mut headers, &build_clear_cookie(ACCESS_TOKEN_COOKIE, "/"));
    append_cookie(
        &mut headers,
        &build_clear_cookie(REFRESH_TOKEN_COOKIE, REFRESH_COOKIE_PATH),
    );
    Ok((
        headers,
        Json(ApiResponse::success(serde_json::json!({ "revoked": true }))),
    ))
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
    let version = repo::revoke_all(state.db(), user_id).await?;
    // Publish the marker so the AuthUser extractor rejects older access tokens at once.
    if let Some(mut redis) = state.revocation_redis() {
        crate::state::mark_user_revoked(&mut redis, user_id, version).await;
    }
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
        fn revocation_redis(&self) -> Option<redis::aio::ConnectionManager> {
            None
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

    // ===================== POST /auth/register =====================

    use shared::auth::encode_phone_verify_token;

    const USER_SECRET: &str =
        "user-secret-at-least-64-characters-long-for-the-hs256-register-test!!!";

    #[derive(Clone)]
    struct RegisterTestDeps {
        db: sqlx::PgPool,
        redis: redis::aio::ConnectionManager,
        ek: EncodingKey,
        dk: DecodingKey,
    }
    impl RegisterDeps for RegisterTestDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn redis(&self) -> redis::aio::ConnectionManager {
            self.redis.clone()
        }
        fn jwt_encoding_key(&self) -> &EncodingKey {
            &self.ek
        }
        fn jwt_decoding_key(&self) -> &DecodingKey {
            &self.dk
        }
    }

    /// Build the register router over a lightweight state. Like otp's handler tests, this is
    /// Redis-gated (state requires a real `ConnectionManager`); without a test Redis it
    /// returns `None` and the caller SKIPs. The lazy DB pool to a closed port is only reached
    /// by paths that get past validation + the single-use GETDEL (the happy path additionally
    /// requires `DATABASE_URL`).
    async fn register_router() -> Option<(Router, redis::aio::ConnectionManager)> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        // Prefer a real DB when DATABASE_URL is set (happy-path test); else a lazy closed pool.
        let db = match std::env::var("DATABASE_URL") {
            Ok(url) => PgPoolOptions::new()
                .acquire_timeout(Duration::from_secs(5))
                .connect(&url)
                .await
                .expect("connect real Postgres"),
            Err(_) => PgPoolOptions::new()
                .acquire_timeout(Duration::from_millis(200))
                .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
                .expect("lazy pool"),
        };
        let deps = RegisterTestDeps {
            db,
            redis: redis.clone(),
            ek: EncodingKey::from_secret(USER_SECRET.as_bytes()),
            dk: DecodingKey::from_secret(USER_SECRET.as_bytes()),
        };
        let app = Router::new()
            .route("/auth/register", post(register::<RegisterTestDeps>))
            .with_state(deps);
        Some((app, redis))
    }

    fn register_body(token: &str, role: &str) -> Body {
        Body::from(
            serde_json::json!({
                "phone_verified_token": token,
                "role": role,
                "pin_hash": "a".repeat(64), // 64-hex SHA-256 shape
            })
            .to_string(),
        )
    }

    async fn post_register(app: Router, body: Body) -> axum::http::Response<Body> {
        app.oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/register")
                .header("content-type", "application/json")
                .body(body)
                .unwrap(),
        )
        .await
        .unwrap()
    }

    /// Admin role can never be self-assigned → 403, BEFORE the OTP token is touched.
    #[tokio::test]
    async fn register_rejects_admin_role() {
        let Some((app, _redis)) = register_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = post_register(app, register_body("any.token.here", "admin")).await;
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    /// A garbage phone-verified token fails signature/decode → 401 (before the GETDEL).
    #[tokio::test]
    async fn register_rejects_garbage_phone_token() {
        let Some((app, _redis)) = register_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = post_register(app, register_body("not.a.valid.jwt", "guard")).await;
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    /// A well-formed phone-verified token whose jti was never stored (or already consumed)
    /// fails the single-use GETDEL → 400. Proves single-use is Redis-enforced.
    #[tokio::test]
    async fn register_rejects_unconsumed_token_missing_jti() {
        let Some((app, _redis)) = register_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let ek = EncodingKey::from_secret(USER_SECRET.as_bytes());
        // Valid signature + purpose, but the jti is NOT in Redis → GETDEL returns nil.
        let (token, _jti) = encode_phone_verify_token("0812345678", &ek, 10).unwrap();
        let res = post_register(app, register_body(&token, "guard")).await;
        assert_eq!(res.status(), StatusCode::BAD_REQUEST);
    }

    /// Full happy path (DATABASE_URL + Redis): a valid, stored phone-verify token registers a
    /// pending account → 202 with a `profile_token` and NO access/refresh tokens or cookies;
    /// the phone-verify jti is consumed (reuse → 400) and a profile jti is now stored.
    #[tokio::test]
    async fn register_happy_path_202_no_tokens_then_single_use() {
        if std::env::var("DATABASE_URL").is_err() {
            eprintln!("SKIP: DATABASE_URL required for the register happy-path test");
            return;
        }
        let Some((app, mut redis)) = register_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };

        let ek = EncodingKey::from_secret(USER_SECRET.as_bytes());
        // A unique 10-digit Thai phone so the UPSERT inserts a fresh row.
        let phone: String = format!(
            "0{}",
            Uuid::new_v4()
                .simple()
                .to_string()
                .chars()
                .filter(|c| c.is_ascii_digit())
                .take(9)
                .collect::<String>()
        );
        let (token, jti) = encode_phone_verify_token(&phone, &ek, 10).unwrap();
        // Store the jti "valid" so the single-use GETDEL succeeds.
        let _: () = redis
            .set_ex(format!("phone_verify_jti:{jti}"), "valid", 600)
            .await
            .expect("seed jti");

        let res = post_register(app.clone(), register_body(&token, "guard")).await;
        assert_eq!(res.status(), StatusCode::ACCEPTED, "register returns 202");
        // No auth cookies on the response.
        assert!(
            res.headers().get(header::SET_COOKIE).is_none(),
            "register must not set auth cookies"
        );

        let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(json["success"], true);
        let data = &json["data"];
        assert!(data["user_id"].is_string(), "carries user_id");
        assert!(data["profile_token"].is_string(), "carries profile_token");
        // CRUCIAL: no access/refresh tokens in the body.
        assert!(data.get("access_token").is_none(), "no access token");
        assert!(data.get("refresh_token").is_none(), "no refresh token");

        // The phone-verify jti was consumed → a reuse of the SAME token now 400s.
        let res2 = post_register(app.clone(), register_body(&token, "guard")).await;
        assert_eq!(
            res2.status(),
            StatusCode::BAD_REQUEST,
            "phone-verify token is single-use"
        );

        let user_id = Uuid::parse_str(data["user_id"].as_str().unwrap()).unwrap();
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&std::env::var("DATABASE_URL").unwrap())
            .await
            .expect("pool");

        // Approve the account, then re-register the SAME phone with a FRESH (seeded) token →
        // the phone is no longer pending → 409 (must log in instead). Closes the contract↔
        // handler loop for the 409 status code at the HTTP layer.
        sqlx::query(
            "UPDATE identity.users SET approval_status = 'approved'::identity.approval_status WHERE id = $1",
        )
        .bind(user_id)
        .execute(&pool)
        .await
        .expect("approve");
        let (token3, jti3) = encode_phone_verify_token(&phone, &ek, 10).unwrap();
        let _: () = redis
            .set_ex(format!("phone_verify_jti:{jti3}"), "valid", 600)
            .await
            .expect("seed jti3");
        let res3 = post_register(app, register_body(&token3, "guard")).await;
        assert_eq!(
            res3.status(),
            StatusCode::CONFLICT,
            "re-registering an approved (non-pending) phone returns 409"
        );

        // cleanup the row we created.
        let _ = sqlx::query("DELETE FROM identity.users WHERE id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
    }
}
