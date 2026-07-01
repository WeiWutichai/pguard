//! API layer — thin Axum transport handlers. No business logic beyond orchestration of
//! `domain` (pure decisions) + `repo` (DB) + JWT/cookie issuance.

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::IntoResponse;
use axum::Json;
use redis::AsyncCommands;
use uuid::Uuid;

use shared::auth::{
    build_clear_cookie, build_cookie, decode_jwt_with_key, decode_phone_verify_token,
    decode_profile_token, encode_jwt_with_key, encode_profile_token, extract_cookie_value,
    AuthUser, ACCESS_TOKEN_COOKIE, PROFILE_PURPOSE_CUSTOMER, PROFILE_PURPOSE_GUARD,
    REFRESH_TOKEN_COOKIE,
};
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::domain::rotation::{decide, RotationDecision};
use crate::domain::{mask, registration, token, twofactor};
use crate::models::{
    ApiTokenView, ChangePasswordRequest, CreateApiTokenRequest, CreateApiTokenResponse,
    Disable2faRequest, Enable2faRequest, Enable2faResponse, EnrollRoleRequest, LoginRequest,
    LoginTokenPair, MeResponse, RefreshRequest, RegisterRequest, RegisterResult,
    ReissueProfileTokenRequest, ResetPinRequest, ResolveUsersRequest, ResolvedUser, SessionView,
    Setup2faResponse, SwitchRoleRequest, TokenPair, TwoFactorChallenge, UpdateMeRequest,
    UserSearchQuery, UserSearchResult, Verify2faRequest, VerifyApiTokenRequest,
    VerifyApiTokenResponse,
};
use crate::repo;
use crate::repo::DeviceContext;
use crate::state::{AppState, RegisterDeps, RevokeAllDeps};

/// Hard cap on the admin user-search result count (a picker page never needs more). A larger
/// requested `limit` is clamped down to this; a non-positive one falls back to the default.
const USER_SEARCH_MAX_LIMIT: i64 = 50;
const USER_SEARCH_DEFAULT_LIMIT: i64 = 20;
/// Hard cap on a single `POST /internal/users/names` batch (one admin page never references more
/// ids than this). A larger batch → 400 (page it), never a silent truncation.
const RESOLVE_USERS_LIMIT: usize = 500;
/// Admin-only role gate label (mirrors profile's `ROLE_ADMIN`).
const ROLE_ADMIN: &str = "admin";

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
/// 2FA login-challenge lifetime (minutes) — short window between password success and the second
/// factor. Generous enough to fetch a code from the authenticator, tight enough to bound replay.
const TWO_FACTOR_CHALLENGE_TTL_MINUTES: i64 = 5;
/// Redis key prefix for the single-use 2FA-challenge jti (mirrors the profile-jti scheme).
const TWO_FACTOR_JTI_PREFIX: &str = "twofa_jti";
/// Max length captured for a stored `User-Agent` (defensive bound; a UA is never legitimately huge).
const MAX_USER_AGENT_LEN: usize = 400;
/// Max `name` length for an admin API token.
const API_TOKEN_NAME_MAX: usize = 80;

/// Extract the device context (User-Agent + client IP) from the request headers for the
/// per-device sessions list (#144). The gateway injects the verified client IP as
/// `X-Forwarded-For`; we take the first hop. The UA is length-bounded. Both are best-effort —
/// a missing header just yields `None`.
fn device_context(headers: &HeaderMap) -> DeviceContext {
    let user_agent = headers
        .get(header::USER_AGENT)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.chars().take(MAX_USER_AGENT_LEN).collect::<String>())
        .filter(|s| !s.is_empty());
    let ip = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.split(',').next())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    DeviceContext { user_agent, ip }
}

/// The 2FA-challenge jti's Redis TTL (challenge JWT lifetime + the same skew buffer the profile
/// token uses), so the single-use marker never expires a hair before the JWT it guards.
fn two_factor_jti_ttl_secs() -> u64 {
    (TWO_FACTOR_CHALLENGE_TTL_MINUTES * 60 + PROFILE_JTI_SKEW_BUFFER_SECS) as u64
}

/// Build the response that carries the token pair both in the JSON body (mobile/API) and
/// as httpOnly Secure SameSite=Lax cookies (web).
fn token_response(pair: TokenPair, access_max_age_secs: i64) -> impl IntoResponse {
    let (headers, _) = token_cookie_headers(&pair, access_max_age_secs);
    (headers, Json(ApiResponse::success(pair)))
}

/// Build the auth Set-Cookie headers for a freshly-issued token pair (access cookie at `/`,
/// refresh cookie scoped to `/auth`). Returns the headers + the pair's access TTL so callers
/// that wrap the pair in a richer body (login's `available_roles`) reuse the identical cookies.
fn token_cookie_headers(pair: &TokenPair, access_max_age_secs: i64) -> (HeaderMap, i64) {
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
    (headers, access_max_age_secs)
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
    headers: HeaderMap,
    Json(req): Json<LoginRequest>,
) -> Result<axum::response::Response, AppError> {
    if req.identifier.trim().is_empty() || req.password.is_empty() {
        // Generic 401 — never reveal which field was the problem.
        return Err(AppError::Unauthorized("Invalid credentials".to_string()));
    }

    let user = repo::verify_credentials(&state.db, req.identifier.trim(), &req.password).await?;

    // 2FA gate (#144): if the account has TOTP enabled, the password is NOT enough — issue a
    // single-use, short-lived challenge token (NO access/refresh tokens, NO session) that the
    // client exchanges at `POST /auth/2fa/verify` with a code. Backward-compatible: an account
    // WITHOUT 2FA logs in exactly as before. Done AFTER credential verification so the existence
    // of 2FA is never an enumeration oracle (an unknown/wrong-password login already 401'd above).
    if repo::totp_enabled_for_user(&state.db, user.id).await? {
        let (challenge_token, jti) = shared::auth::encode_2fa_challenge_token(
            user.id,
            &state.jwt_config.encoding_key,
            TWO_FACTOR_CHALLENGE_TTL_MINUTES,
        )?;
        // Single-use marker (mirrors the profile-token jti scheme): /2fa/verify GETDELs it.
        let mut redis = state.redis_conn.clone();
        redis
            .set_ex::<_, _, ()>(
                format!("{TWO_FACTOR_JTI_PREFIX}:{jti}"),
                "valid",
                two_factor_jti_ttl_secs(),
            )
            .await?;
        tracing::info!(user_id = %user.id, "login: 2FA required (challenge issued)");
        return Ok(Json(ApiResponse::success(TwoFactorChallenge {
            two_factor_required: true,
            challenge_token,
        }))
        .into_response());
    }

    Ok(issue_login_tokens(
        &state,
        user.id,
        &user.role,
        user.token_revocation_version,
        &headers,
    )
    .await?
    .into_response())
}

/// Mint the access token (for `role`) plus a new refresh family and build the LOGIN response
/// (body and cookies), stamping the login device context. Shared by `login` (no-2FA path) and
/// `verify_2fa` (the second factor succeeded), so both issue tokens identically. The body is a
/// `LoginTokenPair`: the usual `TokenPair` fields PLUS `available_roles` (the account's enrolled
/// `user_roles` set) so a multi-role app can offer a role switch. The access token's active role
/// is the supplied `role` (the registration/primary role on login) — unchanged minting
/// behaviour; `available_roles` is additive and backward-compatible.
async fn issue_login_tokens(
    state: &AppState,
    user_id: Uuid,
    role: &str,
    trv: i32,
    headers: &HeaderMap,
) -> Result<axum::response::Response, AppError> {
    let (access_token, _jti) = encode_jwt_with_key(
        user_id,
        role,
        trv as i64,
        &state.jwt_config.encoding_key,
        state.jwt_config.expiry_minutes,
    )?;
    let refresh_token =
        repo::create_refresh_family(&state.db, user_id, &device_context(headers)).await?;

    let pair = TokenPair {
        access_token,
        refresh_token,
        expires_in: state.jwt_config.expiry_minutes * 60,
        token_type: "Bearer",
    };
    // The enrolled-role set for the picker. A single-role user → `[role]` (identical to the
    // single-role world); a dual-role user → both. Always contains the active `role`.
    let available_roles = repo::list_user_roles(&state.db, user_id).await?;

    let (cookie_headers, _) = token_cookie_headers(&pair, state.jwt_config.expiry_minutes * 60);
    let body = LoginTokenPair {
        tokens: pair,
        available_roles,
    };
    Ok((cookie_headers, Json(ApiResponse::success(body))).into_response())
}

// ----- POST /auth/register -----

/// Create an account from a verified phone + chosen role. Returns **202 Accepted** with a
/// single-use `profile_token` and NO access/refresh tokens — the account is `pending` and
/// cannot authenticate until approved (login gates on `approval_status`).
///
/// Order is deliberate: cheap input validation (role/pin shape) runs FIRST so a bad request
/// (e.g. self-assigning `admin`) is rejected WITHOUT burning the user's single-use OTP token;
/// then the phone-verify token is verified (signature/purpose/expiry); then the account row is
/// UPSERTed; and ONLY THEN is the single-use jti atomically consumed (GETDEL). Deferring the
/// GETDEL until after the UPSERT commits means a transient UPSERT/profile-token failure returns
/// 500 WITHOUT consuming the jti, so the client can safely retry with the same token instead of
/// being stranded on "already used". The UPSERT's `ON CONFLICT WHERE pending` idempotency
/// absorbs a rare double-submit that races in before the consume.
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

    // 4) UPSERT the pending account FIRST (Argon2 of pin_hash happens inside repo via
    //    spawn_blocking). A non-pending phone → Conflict ("log in instead"). The UPSERT is
    //    idempotent (ON CONFLICT WHERE pending), so a rare double-submit racing in before the
    //    one-time GETDEL claim below is absorbed rather than losing the account row.
    //    The phone-verify token's signature/purpose/expiry were already validated above; only
    //    the single-use GETDEL claim is deferred to after the account row is committed so that
    //    a failed UPSERT or profile_token write does NOT consume the jti and strand the user
    //    on retry (same token → "already used").
    let user_id =
        repo::upsert_pending_user(state.db(), &phone, &role.to_string(), &req.pin_hash).await?;

    // 5) Single-use: atomically claim the jti (GETDEL) AFTER the account row is committed. A
    //    reused/expired/forged token has no live "valid" marker → reject. Running it here (not
    //    before the UPSERT) keeps the token replayable until the account exists, so a transient
    //    UPSERT failure leaves the client free to retry with the same token.
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

// ----- POST /auth/register/reissue -----

/// Switch a still-PENDING account's role WITHOUT re-OTP. The single-use `phone_verified_token`
/// is already spent by the first `register`, so the onboarding "back → pick another role" path
/// authenticates with the still-valid `profile_token` from that register (presented as the Bearer):
/// we decode it (either onboarding purpose) to the `user_id`, update the role (pending accounts
/// only), CONSUME the old profile token's jti, and mint+return a fresh profile_token for the new
/// role. The phone-verify token stays single-use; only the role choice is reversible, and only
/// within the profile token's short lifetime.
#[tracing::instrument(skip_all)]
pub async fn reissue_profile_token<S: RegisterDeps>(
    State(state): State<S>,
    headers: HeaderMap,
    Json(req): Json<ReissueProfileTokenRequest>,
) -> Result<impl IntoResponse, AppError> {
    let role = registration::validate_registration_role(&req.role)?;

    // Auth: the prior register's profile_token (Bearer). Accept EITHER onboarding purpose so a
    // guard→customer (or customer→guard) switch both resolve; a doc-upload / access / forged token
    // matches neither and is rejected. The decode also yields the old jti to consume.
    let presented = headers
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.strip_prefix("Bearer "))
        .ok_or_else(|| AppError::Unauthorized("Missing registration token".to_string()))?;
    let (user_id, old_jti) =
        decode_profile_token(presented, state.jwt_decoding_key(), PROFILE_PURPOSE_GUARD)
            .or_else(|_| {
                decode_profile_token(
                    presented,
                    state.jwt_decoding_key(),
                    PROFILE_PURPOSE_CUSTOMER,
                )
            })
            .map_err(|_| {
                AppError::Unauthorized("Registration token is invalid or expired".to_string())
            })?;

    // Consume the OLD profile token's jti FIRST (atomic single-use claim). A spent (e.g. already
    // submitted at /profile/*), expired, or forged token has no live "valid" marker → reject. Doing
    // this BEFORE the role write means a stale-token replay performs no side effect, and an
    // already-used profile_token can't be resurrected into a fresh one. Mirrors register's
    // phone-verify consume and the profile service's profile_jti consume.
    let mut redis = state.redis();
    let old_status: Option<String> = redis::cmd("GETDEL")
        .arg(format!("profile_jti:{old_jti}"))
        .query_async(&mut redis)
        .await?;
    if old_status.as_deref() != Some("valid") {
        return Err(AppError::Unauthorized(
            "Registration token is invalid, expired, or already used".to_string(),
        ));
    }

    // Update the role — pending accounts only (a non-pending phone → Conflict: "log in instead").
    repo::update_pending_user_role(state.db(), user_id, &role.to_string()).await?;

    // Mint the new-role profile token (same TTL + jti marker as register step 6).
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

    tracing::info!(%user_id, role = %role, "pending account role switched (profile token reissued)");

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

            let Some(refresh_token) = repo::rotate(
                &state.db,
                located.user_id,
                located.family_id,
                rotation_id,
                &device_context(&headers),
            )
            .await?
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

/// The caller's own `{ user_id, role, display_name, email }`. The role still comes from the
/// validated access token (cheap, authoritative); `display_name` + `email` are read from the DB by
/// `user_id` (#144 — admins finally carry a human name). A soft-deleted row → 404 (the token check
/// already rejects an erased account via the `trv` marker, so this is defense-in-depth).
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn me(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<ApiResponse<MeResponse>>, AppError> {
    let profile = repo::self_profile(&state.db, user.user_id).await?;
    // The multi-role set (Option A). For a single-role user this is exactly `[role]`; for a
    // dual-role user it carries both so the app can offer a role switch. The ACTIVE `role`
    // below is still the token's role (authoritative for this session).
    let roles = repo::list_user_roles(&state.db, user.user_id).await?;
    Ok(Json(ApiResponse::success(MeResponse {
        user_id: user.user_id,
        // Prefer the freshly-read DB role (authoritative if it changed since the token issued);
        // falls back identically to the token's role in the common case.
        role: profile.role,
        roles,
        display_name: profile.display_name,
        email: profile.email,
    })))
}

// ----- PUT /auth/me (self-edit display_name + email) -----

/// Update the CALLER'S OWN `display_name` + `email` (#144 admin self-profile). Self-only — keyed by
/// the authenticated `user.user_id`; phone/role/password are never touched here. `display_name` is
/// trimmed + bounded (1..=120 chars); `email` is optional, lowercased + shape-checked, and UNIQUE
/// (a collision → 409 `EMAIL_TAKEN`). Returns the refreshed self-profile.
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn update_me(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<UpdateMeRequest>,
) -> Result<Json<ApiResponse<MeResponse>>, AppError> {
    let display_name = registration::validate_display_name(&req.display_name)?;
    let email = registration::validate_email(req.email.as_deref())?;
    let profile =
        repo::update_self_profile(&state.db, user.user_id, &display_name, email.as_deref()).await?;
    let roles = repo::list_user_roles(&state.db, user.user_id).await?;
    Ok(Json(ApiResponse::success(MeResponse {
        user_id: user.user_id,
        role: profile.role,
        roles,
        display_name: profile.display_name,
        email: profile.email,
    })))
}

// ----- PUT /auth/password (self change-password) -----

/// Change the caller's OWN password (#144). Verifies `current_password` (Argon2, generic 401 on
/// mismatch — no enumeration), then Argon2-stores `new_pin_hash` and force-revokes the user's
/// OTHER sessions (refresh families revoked + `trv` bumped, so every other device is rejected at
/// once) and clears THIS browser's auth cookies so the current session re-authenticates too.
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn change_password(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<ChangePasswordRequest>,
) -> Result<impl IntoResponse, AppError> {
    // Shape-check the NEW pin_hash up front (same 64-hex SHA-256 contract as register's pin_hash);
    // the current password is verified by the repo against the stored Argon2 hash.
    registration::validate_pin_hash(&req.new_pin_hash)?;

    let new_version = repo::change_password(
        &state.db,
        user.user_id,
        &req.current_password,
        &req.new_pin_hash,
    )
    .await?;

    // Force-revoke the OTHER sessions immediately: publish the new revocation marker so any
    // outstanding access token (older `trv`) is rejected at once. A persistent marker-write
    // failure propagates (500) so the client knows revocation isn't fully effective.
    let mut redis = state.redis_conn.clone();
    crate::state::mark_user_revoked(&mut redis, user.user_id, new_version).await?;

    // Clear THIS browser's cookies — the caller re-authenticates with the new PIN.
    let mut headers = HeaderMap::new();
    append_cookie(&mut headers, &build_clear_cookie(ACCESS_TOKEN_COOKIE, "/"));
    append_cookie(
        &mut headers,
        &build_clear_cookie(REFRESH_TOKEN_COOKIE, REFRESH_COOKIE_PATH),
    );
    Ok((
        headers,
        Json(ApiResponse::success(
            serde_json::json!({ "password_changed": true }),
        )),
    ))
}

// ----- POST /auth/reset-pin (forgot-PIN reset via OTP) -----

/// Reset a FORGOTTEN PIN. Authorized ENTIRELY by a single-use `phone_verified_token` from the OTP
/// flow — the phone comes from that token, NEVER the body — so a caller can only reset the PIN of a
/// phone they just proved they own (received the SMS for). No current PIN is required (they forgot
/// it). On success: store the new Argon2 hash, bump the revocation version + revoke every refresh
/// family (a reset kills ALL sessions), then force-revoke outstanding access tokens via the Redis
/// `trv` marker. Edge-public (carries the purpose token in the body, not an access token).
/// `skip_all`: never log the token, the pin_hash, or the phone (PII).
#[tracing::instrument(skip_all)]
pub async fn reset_pin(
    State(state): State<AppState>,
    Json(req): Json<ResetPinRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    // 1) Shape-check the NEW pin_hash up front (same 64-hex SHA-256 contract as register's pin_hash).
    registration::validate_pin_hash(&req.new_pin_hash)?;

    // 2) Verify the phone-verified token (signature + purpose + expiry). The phone is FROM the token,
    //    never the body — this is the whole authorization for the reset.
    let (phone, jti) =
        decode_phone_verify_token(&req.phone_verified_token, &state.jwt_config.decoding_key)?;
    let phone = registration::validate_thai_phone(&phone)?;

    // 3) Claim the single-use jti FIRST (GETDEL). Unlike register (whose account UPSERT is
    //    idempotent, so it defers the claim to stay retryable), a PIN reset is a NON-idempotent
    //    credential change — claim before mutating so a reused/forged/expired token can NEVER drive
    //    a second reset. A missing "valid" marker → reject before touching the account.
    let mut redis = state.redis_conn.clone();
    let jti_status: Option<String> = redis::cmd("GETDEL")
        .arg(format!("phone_verify_jti:{jti}"))
        .query_async(&mut redis)
        .await?;
    if jti_status.as_deref() != Some("valid") {
        return Err(AppError::BadRequest(
            "Phone verification token is invalid, expired, or already used".to_string(),
        ));
    }

    // 4) Reset the PIN of the account holding the token's phone (new Argon2 hash + bump trv + revoke
    //    all refresh families). `None` = no active account for that phone → they should register.
    let Some((user_id, new_version)) =
        repo::reset_password_by_phone(&state.db, &phone, &req.new_pin_hash).await?
    else {
        return Err(AppError::BadRequest(
            "No account found for this phone — please register".to_string(),
        ));
    };

    // 5) Force-revoke outstanding ACCESS tokens at once (any older `trv` is rejected) — a persistent
    //    marker-write failure propagates (500) so the client knows the revocation isn't yet effective.
    crate::state::mark_user_revoked(&mut redis, user_id, new_version).await?;

    Ok(Json(ApiResponse::success(
        serde_json::json!({ "pin_reset": true }),
    )))
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

    // Reject every outstanding access token immediately (force-revoke-all marker). A persistent
    // marker-write failure propagates as 500 so the client knows revocation isn't fully
    // effective (in-flight access tokens would otherwise live until natural expiry).
    let mut redis = state.redis_conn.clone();
    crate::state::mark_user_revoked(&mut redis, user.user_id, new_version).await?;

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
    // Propagate a persistent marker-write failure (500) rather than reporting a revoke that
    // wouldn't actually reject in-flight access tokens.
    let mut redis = state.redis_conn.clone();
    crate::state::mark_user_revoked(&mut redis, user.user_id, version).await?;

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

// ===================== Multi-role (Option A) =====================

// ----- POST /auth/switch-role (authenticated self) -----

/// Switch the caller's ACTIVE role and mint a NEW access+refresh token pair stamped with that
/// role. THE CRITICAL SECURITY GATE: the target `role` MUST be in the caller's APPROVED
/// `user_roles` set — checked via `repo::user_has_role` BEFORE any token is minted. A role the
/// user is not enrolled in → 409 `ROLE_NOT_ENROLLED` and NO token is issued (no privilege
/// escalation: a customer can never mint a guard token unless they hold an approved guard
/// profile, and vice-versa). On success a fresh refresh FAMILY is created (like a normal login —
/// the old family is left intact so the user's other sessions keep their prior role until they
/// expire/refresh), and the pair is returned in the body + as cookies. `admin` can never be a
/// switch target because it can never enter `user_roles` (no self-assignment at registration and
/// no admin profile route to approve). `skip_all`: never log tokens.
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn switch_role(
    State(state): State<AppState>,
    user: AuthUser,
    headers: HeaderMap,
    Json(req): Json<SwitchRoleRequest>,
) -> Result<axum::response::Response, AppError> {
    // Normalize + reject structurally-impossible targets (unknown role → BadRequest; admin →
    // Forbidden) BEFORE the enrolment check, so the 409 is reserved for a real "valid role you
    // simply aren't enrolled in" — not a typo or an escalation attempt.
    let role = registration::validate_registration_role(&req.role)?;
    let role = role.to_string();

    // THE gate: only an ENROLLED role can be switched into. A non-enrolled role mints NOTHING.
    if !repo::user_has_role(&state.db, user.user_id, &role).await? {
        return Err(AppError::ConflictCode {
            code: "ROLE_NOT_ENROLLED",
            message: "You are not enrolled in that role. Register it first.".to_string(),
        });
    }

    // Re-read the current revocation version for the new token (the account must still be live).
    let trv = repo::user_trv_if_active(&state.db, user.user_id)
        .await?
        .ok_or_else(|| AppError::Unauthorized("Account is no longer eligible".to_string()))?;

    let (access_token, _jti) = encode_jwt_with_key(
        user.user_id,
        &role,
        trv as i64,
        &state.jwt_config.encoding_key,
        state.jwt_config.expiry_minutes,
    )?;
    let refresh_token =
        repo::create_refresh_family(&state.db, user.user_id, &device_context(&headers)).await?;

    let pair = TokenPair {
        access_token,
        refresh_token,
        expires_in: state.jwt_config.expiry_minutes * 60,
        token_type: "Bearer",
    };
    tracing::info!(role = %role, "active role switched (new token pair minted)");
    Ok(token_response(pair, state.jwt_config.expiry_minutes * 60).into_response())
}

// ----- POST /auth/roles (authenticated self — enroll a NEW role) -----

/// Enroll the logged-in user in a NEW role they don't yet hold. Returns a single-use
/// `profile_token` scoped to `(this user_id, the new role)` — the SAME shape register issues — so
/// the app can submit that role's profile form (`POST /profile/{guard,customer}`), creating a
/// PENDING second profile for the SAME user_id. The role enters `user_roles` (becomes switchable)
/// ONLY on admin approval (the `user.approved` event path). This endpoint does NOT grant the role.
///
/// 409 if the caller is ALREADY enrolled in `role` (it's in `user_roles`). A role with a still-
/// pending profile is NOT a hard error here: re-issuing the `profile_token` is idempotent (the
/// profile upsert refreshes the existing pending row), and identity does not synchronously couple
/// to profile to probe pending state (no cross-service read in the request path). `admin` is
/// rejected (Forbidden) — no profile route, never self-assignable. `skip_all`: never log tokens.
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn enroll_role(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<EnrollRoleRequest>,
) -> Result<impl IntoResponse, AppError> {
    // Validate the target (unknown → BadRequest; admin → Forbidden — no self-assignment, no
    // profile route). Only guard/customer reach the enrolment path.
    let role = registration::validate_registration_role(&req.role)?;

    // Already enrolled (approved) → 409. The role is live/switchable already; nothing to do.
    if repo::user_has_role(&state.db, user.user_id, &role.to_string()).await? {
        return Err(AppError::ConflictCode {
            code: "ROLE_ALREADY_ENROLLED",
            message: "You already hold that role.".to_string(),
        });
    }

    // Mint the single-use profile_token for THIS user_id + the new role's onboarding route, and
    // record its jti so the profile service can GETDEL it once (identical scheme to register
    // step 6). The token's `sub` is the EXISTING user_id, so the pending profile is created for
    // the SAME account — the profile tables allow one guard_profile AND one customer_profile per
    // user_id, so a second-role profile coexists with the first.
    let purpose = registration::profile_purpose_for_role(&role)?;
    let (profile_token, profile_jti) = encode_profile_token(
        user.user_id,
        purpose,
        &state.jwt_config.encoding_key,
        PROFILE_TOKEN_TTL_MINUTES,
    )?;
    let ttl_secs = (PROFILE_TOKEN_TTL_MINUTES * 60 + PROFILE_JTI_SKEW_BUFFER_SECS) as u64;
    let mut redis = state.redis_conn.clone();
    redis
        .set_ex::<_, _, ()>(format!("profile_jti:{profile_jti}"), "valid", ttl_secs)
        .await?;

    tracing::info!(role = %role, "new role enrollment started (pending second profile)");
    Ok((
        StatusCode::ACCEPTED,
        Json(ApiResponse::success(RegisterResult {
            user_id: user.user_id,
            profile_token,
        })),
    ))
}

// ===================== 2FA (#144 admin security) =====================

// ----- POST /auth/2fa/setup (provision, NOT yet enabled) -----

/// Begin TOTP enrollment for the CALLER. Generates a fresh secret, SEALS it at rest (AES-256-GCM
/// under `TOTP_ENC_KEY`), stores it as the provisioning secret (2FA still OFF), and returns the
/// `otpauth://` URI (for the QR) + the base32 secret (manual entry). 2FA is enabled only after the
/// user proves a live code at `/2fa/enable`. Calling setup again before enabling simply re-provisions.
/// `skip_all`: never log the secret / URI.
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn setup_2fa(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Setup2faResponse>>, AppError> {
    // The account label shown in the authenticator app — the phone (account's stable handle).
    let row = repo::totp_row(&state.db, user.user_id).await?;
    if row.totp_enabled {
        // Already on — disable first (so a stray setup can't silently rotate a live secret).
        return Err(AppError::Conflict(
            "2FA is already enabled. Disable it first to re-enroll.".to_string(),
        ));
    }
    let secret = twofactor::generate_totp_secret();
    let (otpauth_uri, base32) = twofactor::provisioning(&secret, &row.phone)?;
    let sealed = twofactor::seal_secret(&state.totp_enc_key, &secret)?;
    repo::store_provisioned_totp(&state.db, user.user_id, &sealed).await?;
    tracing::info!("2FA provisioning secret issued");
    Ok(Json(ApiResponse::success(Setup2faResponse {
        otpauth_uri,
        secret: base32,
    })))
}

// ----- POST /auth/2fa/enable -----

/// Turn 2FA ON for the CALLER after verifying a live TOTP `code` against the provisioning secret
/// from `/2fa/setup`. On success, flips `totp_enabled`, regenerates the one-time recovery codes,
/// and returns them ONCE. A wrong code → 401 (nothing changes); no provisioning in progress → 409.
/// `skip_all`: never log the code / secret / recovery codes.
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn enable_2fa(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<Enable2faRequest>,
) -> Result<Json<ApiResponse<Enable2faResponse>>, AppError> {
    let row = repo::totp_row(&state.db, user.user_id).await?;
    if row.totp_enabled {
        return Err(AppError::Conflict("2FA is already enabled.".to_string()));
    }
    let sealed = row.totp_secret_enc.ok_or_else(|| {
        AppError::Conflict("No 2FA setup in progress — call /2fa/setup first.".to_string())
    })?;
    let secret = twofactor::open_secret(&state.totp_enc_key, &sealed)?;
    if !twofactor::verify_totp(&secret, &row.phone, &req.code)? {
        return Err(AppError::Unauthorized("Invalid 2FA code".to_string()));
    }

    // Mint + persist the recovery codes (store hashes only), flip the flag in one tx.
    let codes = twofactor::generate_recovery_codes();
    let hashes: Vec<String> = codes.iter().map(|(_, h)| h.clone()).collect();
    repo::enable_totp_with_recovery_codes(&state.db, user.user_id, &hashes).await?;
    tracing::info!("2FA enabled");
    Ok(Json(ApiResponse::success(Enable2faResponse {
        recovery_codes: codes.into_iter().map(|(plain, _)| plain).collect(),
    })))
}

// ----- POST /auth/2fa/disable -----

/// Turn 2FA OFF for the CALLER. Requires confirmation via EITHER a live TOTP `code` OR the account
/// `password` (so a momentary unlocked session can't silently weaken the account without a factor).
/// Clears the secret + recovery codes. A wrong code/password → 401. `skip_all`: never log secrets.
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn disable_2fa(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<Disable2faRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let row = repo::totp_row(&state.db, user.user_id).await?;
    if !row.totp_enabled {
        // Idempotent-friendly: already off.
        return Ok(Json(ApiResponse::success(
            serde_json::json!({ "two_factor_enabled": false }),
        )));
    }

    // Confirm intent: a live TOTP code OR the password (at least one must verify).
    let confirmed = match (&req.code, &req.password) {
        (Some(code), _) if !code.trim().is_empty() => {
            let sealed = row.totp_secret_enc.clone().ok_or_else(|| {
                AppError::Internal("2FA enabled without a stored secret".to_string())
            })?;
            let secret = twofactor::open_secret(&state.totp_enc_key, &sealed)?;
            twofactor::verify_totp(&secret, &row.phone, code)?
        }
        (_, Some(password)) if !password.is_empty() => {
            let password = password.clone();
            let hash = row.password_hash.clone();
            tokio::task::spawn_blocking(move || {
                crate::domain::password::verify_secret(&password, &hash)
            })
            .await
            .map_err(|e| AppError::Internal(format!("verify task failed: {e}")))??
        }
        _ => {
            return Err(AppError::BadRequest(
                "Provide a 2FA code or your password to disable 2FA.".to_string(),
            ))
        }
    };
    if !confirmed {
        return Err(AppError::Unauthorized("Invalid credentials".to_string()));
    }

    repo::disable_totp(&state.db, user.user_id).await?;
    tracing::info!("2FA disabled");
    Ok(Json(ApiResponse::success(
        serde_json::json!({ "two_factor_enabled": false }),
    )))
}

// ----- POST /auth/2fa/verify (second login step) -----

/// Complete a 2FA login: validate the single-use `challenge_token` (issued by `/auth/login` when
/// 2FA is enabled), verify EITHER a TOTP `code` OR a one-time `recovery_code`, then issue the real
/// token pair (same as a normal login). The challenge jti is consumed (GETDEL) up front so a stolen
/// challenge can't be replayed. A recovery code is single-use (consumed atomically). Edge-public
/// (it carries a purpose token, not an access token). `skip_all`: never log the codes/tokens.
#[tracing::instrument(skip_all)]
pub async fn verify_2fa(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<Verify2faRequest>,
) -> Result<axum::response::Response, AppError> {
    // 1) Decode the challenge token (purpose-isolated) → user_id + jti.
    let (user_id, jti) = shared::auth::decode_2fa_challenge_token(
        &req.challenge_token,
        &state.jwt_config.decoding_key,
    )
    .map_err(|_| AppError::Unauthorized("Invalid or expired 2FA challenge".to_string()))?;

    // 2) Single-use: GETDEL the challenge jti FIRST (a replayed/expired challenge has no live
    //    marker → reject before touching any code).
    let mut redis = state.redis_conn.clone();
    let claim: Option<String> = redis::cmd("GETDEL")
        .arg(format!("{TWO_FACTOR_JTI_PREFIX}:{jti}"))
        .query_async(&mut redis)
        .await?;
    if claim.as_deref() != Some("valid") {
        return Err(AppError::Unauthorized(
            "2FA challenge is invalid, expired, or already used".to_string(),
        ));
    }

    // 3) Load the account's 2FA state (must still be enabled).
    let row = repo::totp_row(&state.db, user_id).await?;
    if !row.totp_enabled {
        return Err(AppError::Unauthorized("2FA is not enabled".to_string()));
    }

    // 4) Verify a TOTP code, else a one-time recovery code.
    let ok = if let Some(code) = req.code.as_deref().filter(|c| !c.trim().is_empty()) {
        let sealed = row
            .totp_secret_enc
            .clone()
            .ok_or_else(|| AppError::Internal("2FA enabled without a stored secret".to_string()))?;
        let secret = twofactor::open_secret(&state.totp_enc_key, &sealed)?;
        twofactor::verify_totp(&secret, &row.phone, code)?
    } else if let Some(rc) = req
        .recovery_code
        .as_deref()
        .filter(|c| !c.trim().is_empty())
    {
        let hash = twofactor::sha256_hex(&twofactor::normalize_recovery_code(rc));
        repo::consume_recovery_code(&state.db, user_id, &hash).await?
    } else {
        return Err(AppError::BadRequest(
            "Provide a 2FA code or a recovery code.".to_string(),
        ));
    };
    if !ok {
        return Err(AppError::Unauthorized("Invalid 2FA code".to_string()));
    }

    // 5) Re-read the user's CURRENT role + revocation version, then issue the token pair (the
    //    challenge proved the password; this proves the second factor).
    let meta = repo::user_auth_meta(&state.db, user_id)
        .await?
        .ok_or_else(|| AppError::Unauthorized("Account is no longer eligible".to_string()))?;
    tracing::info!(%user_id, "2FA verified — issuing tokens");
    Ok(issue_login_tokens(
        &state,
        meta.id,
        &meta.role,
        meta.token_revocation_version,
        &headers,
    )
    .await?
    .into_response())
}

// ===================== Per-device sessions (#144) =====================

// ----- GET /auth/sessions -----

/// List the CALLER'S active sessions (refresh families) as a device list. `current` marks the
/// session whose refresh token is presented (cookie or `X-Refresh-Token` header) so the UI can
/// label "this device". `ip` is masked to its first two octets (last two redacted) — enough to
/// recognise a network without exposing the full address.
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn list_sessions(
    State(state): State<AppState>,
    user: AuthUser,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<Vec<SessionView>>>, AppError> {
    let rows = repo::list_sessions(&state.db, user.user_id).await?;

    // Resolve the caller's CURRENT family from the presented refresh token (cookie, or the
    // `X-Refresh-Token` header for mobile/API clients that don't use cookies). Best-effort —
    // if absent/unparseable, no row is flagged current (the list is still correct).
    let current_family = current_refresh_family(&state, &headers).await;

    let views = rows
        .into_iter()
        .map(|r| SessionView {
            current: Some(r.family_id) == current_family,
            family_id: r.family_id,
            user_agent: r.user_agent,
            ip: r.ip.as_deref().map(mask::mask_ip),
            created_at: r.created_at,
            last_used_at: r.last_used_at,
        })
        .collect();
    Ok(Json(ApiResponse::success(views)))
}

/// Resolve the caller's CURRENT refresh family from the presented refresh token (cookie or
/// `X-Refresh-Token` header), or `None`. Used only to flag the `current` session — never an
/// auth decision, so a miss is harmless.
async fn current_refresh_family(state: &AppState, headers: &HeaderMap) -> Option<Uuid> {
    let presented = headers
        .get("x-refresh-token")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .or_else(|| {
            headers
                .get(header::COOKIE)
                .and_then(|v| v.to_str().ok())
                .and_then(|c| extract_cookie_value(c, REFRESH_TOKEN_COOKIE))
                .map(|t| t.to_string())
        })?;
    let (rotation_id, _) = token::parse(&presented)?;
    let located = repo::find_refresh_by_rotation(&state.db, rotation_id)
        .await
        .ok()??;
    Some(located.family_id)
}

// ----- DELETE /auth/sessions/{family_id} -----

/// Revoke ONE of the caller's OWN sessions (sign out a single device, #144). Ownership-scoped to
/// the caller (a family that isn't theirs → 404, IDOR-safe). The existing "revoke-all" stays as a
/// separate endpoint. The revoked device's refresh token can no longer rotate; its access token
/// expires naturally (≤15 min) — same model as logout.
#[tracing::instrument(skip_all, fields(user = %user.user_id, family = %family_id))]
pub async fn revoke_session(
    State(state): State<AppState>,
    user: AuthUser,
    Path(family_id): Path<Uuid>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    repo::revoke_own_family(&state.db, user.user_id, family_id).await?;
    tracing::info!("session revoked (single device)");
    Ok(Json(ApiResponse::success(
        serde_json::json!({ "revoked": true }),
    )))
}

// ===================== Admin API tokens (#144) =====================

// ----- POST /admin/api-tokens -----

/// Create a long-lived admin API token for the CALLER. ADMIN-ONLY (else 403). Returns the FULL
/// token (`pguard_<prefix>_<secret>`) EXACTLY ONCE — only the SHA-256 hash of the secret is stored,
/// so it can never be shown again. The token authenticates as the creator's role (admin).
/// `skip_all`: never log the token.
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn create_api_token(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreateApiTokenRequest>,
) -> Result<Json<ApiResponse<CreateApiTokenResponse>>, AppError> {
    if user.role != ROLE_ADMIN {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let name = req.name.trim();
    if name.is_empty() || name.chars().count() > API_TOKEN_NAME_MAX {
        return Err(AppError::BadRequest(format!(
            "name is required and must be ≤ {API_TOKEN_NAME_MAX} characters"
        )));
    }
    let minted = twofactor::generate_api_token();
    let id = repo::create_api_token(
        &state.db,
        user.user_id,
        name,
        &minted.prefix,
        &minted.secret_hash,
        &user.role,
    )
    .await?;
    tracing::info!(token_id = %id, "admin API token created");
    Ok(Json(ApiResponse::success(CreateApiTokenResponse {
        id,
        name: name.to_string(),
        prefix: minted.prefix,
        token: minted.full,
    })))
}

// ----- GET /admin/api-tokens -----

/// List the CALLER'S admin API tokens (NEVER the secret). ADMIN-ONLY. `revoked` is derived; a
/// revoked token is shown (for audit) but cannot authenticate.
#[tracing::instrument(skip_all, fields(user = %user.user_id))]
pub async fn list_api_tokens(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<ApiTokenView>>>, AppError> {
    if user.role != ROLE_ADMIN {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let rows = repo::list_api_tokens(&state.db, user.user_id).await?;
    let views = rows
        .into_iter()
        .map(|r| ApiTokenView {
            id: r.id,
            name: r.name,
            prefix: r.prefix,
            role: r.role,
            created_at: r.created_at,
            last_used_at: r.last_used_at,
            revoked: r.revoked_at.is_some(),
        })
        .collect();
    Ok(Json(ApiResponse::success(views)))
}

// ----- DELETE /admin/api-tokens/{id} -----

/// Revoke ONE of the caller's OWN admin API tokens by id. ADMIN-ONLY + ownership-scoped (a token
/// that isn't theirs → 404, IDOR-safe). Soft-revoke (the row is kept for audit); a revoked token
/// fails verification immediately.
#[tracing::instrument(skip_all, fields(user = %user.user_id, token = %token_id))]
pub async fn revoke_api_token(
    State(state): State<AppState>,
    user: AuthUser,
    Path(token_id): Path<Uuid>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    if user.role != ROLE_ADMIN {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    repo::revoke_api_token(&state.db, user.user_id, token_id).await?;
    tracing::info!("admin API token revoked");
    Ok(Json(ApiResponse::success(
        serde_json::json!({ "revoked": true }),
    )))
}

// ----- POST /internal/api-tokens/verify (service-JWT only; the gateway calls this) -----

/// Verify a presented `pguard_…` API token (service-to-service). The gateway, on seeing a bearer
/// with the `pguard_` namespace, calls THIS endpoint (service-JWT'd) to resolve the principal; on
/// success it injects the trusted `X-User-*` and proxies. Looks the token up by its public prefix,
/// constant-time-compares the secret hash, checks the owner is still active/approved, and stamps
/// `last_used_at`. A bad/revoked/unknown token → 401. Generic over [`RevokeAllDeps`] so the
/// service-JWT guard is testable in isolation (reuses the `db()` seam). `skip_all`: never log the token.
#[tracing::instrument(skip_all)]
pub async fn internal_verify_api_token<S: RevokeAllDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Json(req): Json<VerifyApiTokenRequest>,
) -> Result<Json<ApiResponse<VerifyApiTokenResponse>>, AppError> {
    let generic_401 = || AppError::Unauthorized("Invalid API token".to_string());
    let (prefix, secret) = twofactor::parse_api_token(&req.token).ok_or_else(generic_401)?;

    let row = repo::find_api_token_by_prefix(state.db(), &prefix)
        .await?
        .ok_or_else(generic_401)?;
    // Constant-time hash compare (anti-timing); a mismatch is the same generic 401.
    if !twofactor::api_token_secret_matches(&secret, &row.token_hash) {
        return Err(generic_401());
    }
    // Best-effort freshness stamp (a hiccup must not fail an otherwise-valid auth).
    if let Err(e) = repo::touch_api_token(state.db(), row.token_id).await {
        tracing::warn!("failed to stamp api-token last_used_at: {e}");
    }
    tracing::debug!(caller = %caller.service, user_id = %row.user_id, "API token verified");
    Ok(Json(ApiResponse::success(VerifyApiTokenResponse {
        user_id: row.user_id,
        role: row.role,
    })))
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
    // Publish the marker so the AuthUser extractor rejects older access tokens at once. A
    // persistent failure propagates (500) so the calling service learns revocation isn't fully
    // effective rather than getting a false 200.
    if let Some(mut redis) = state.revocation_redis() {
        crate::state::mark_user_revoked(&mut redis, user_id, version).await?;
    }
    Ok(Json(ApiResponse::success(())))
}

// ----- POST /internal/users/names (service-JWT only) -----

/// Resolve a batch of `user_id`s to `{ role, display_name }` for an internal caller (the profile
/// service's `/admin/users/resolve` merges admin names from here — closing the Activity Log #142
/// gap where admins had no name). Service-JWT-gated ([`ServiceCaller`]; blocked at the edge), so it
/// is never publicly reachable. Returns a MAP keyed by id; unknown/deleted ids are OMITTED. ONLY
/// `role` + `display_name` — NEVER phone/email. Bounded to `RESOLVE_USERS_LIMIT` ids; a larger
/// batch → 400 (page it). Generic over [`RevokeAllDeps`] so the service-JWT guard is testable
/// in isolation (reuses the same `db()` + `HasServiceJwt` seam as `internal_revoke_all`).
pub async fn internal_resolve_users<S: RevokeAllDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Json(req): Json<ResolveUsersRequest>,
) -> Result<Json<ApiResponse<std::collections::HashMap<Uuid, ResolvedUser>>>, AppError> {
    if req.ids.len() > RESOLVE_USERS_LIMIT {
        return Err(AppError::BadRequest(format!(
            "too many ids (max {RESOLVE_USERS_LIMIT} per request — page the calls)"
        )));
    }
    tracing::debug!(caller = %caller.service, count = req.ids.len(), "internal resolve-users");
    // De-duplicate before the query (a page can reference the same admin on many rows).
    let ids: Vec<Uuid> = {
        let mut seen = std::collections::HashSet::new();
        req.ids.into_iter().filter(|id| seen.insert(*id)).collect()
    };
    let rows = repo::resolve_users(state.db(), &ids).await?;
    let map: std::collections::HashMap<Uuid, ResolvedUser> = rows
        .into_iter()
        .map(|r| {
            (
                r.user_id,
                ResolvedUser {
                    role: r.role,
                    display_name: r.display_name,
                },
            )
        })
        .collect();
    Ok(Json(ApiResponse::success(map)))
}

// ----- GET /admin/users/search (admin-only) -----

/// Search users for the admin per-user-notify picker (#138). ADMIN ONLY (else 403, before any DB
/// access). Finds users by `display_name` / `phone` / `email` / exact id across ALL roles, returns
/// `[{ id, role, display_name, phone_masked }]` — the phone is MASKED (last-4) and NO other PII
/// (email/bank/address never cross the wire). `limit` is clamped to `USER_SEARCH_MAX_LIMIT`. A
/// blank `q` returns an empty list (no full-table dump).
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn admin_search_users(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<UserSearchQuery>,
) -> Result<Json<ApiResponse<Vec<UserSearchResult>>>, AppError> {
    if user.role != ROLE_ADMIN {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let query = q.q.as_deref().map(str::trim).unwrap_or("");
    // A blank query must not page the whole user table.
    if query.is_empty() {
        return Ok(Json(ApiResponse::success(Vec::new())));
    }
    let limit = match q.limit {
        Some(n) if n > 0 => n.min(USER_SEARCH_MAX_LIMIT),
        _ => USER_SEARCH_DEFAULT_LIMIT,
    };
    let rows = repo::search_users(&state.db, query, limit).await?;
    let results = rows
        .into_iter()
        .map(|r| UserSearchResult {
            id: r.user_id,
            role: r.role,
            display_name: r.display_name,
            phone_masked: mask::mask_phone(&r.phone),
        })
        .collect();
    Ok(Json(ApiResponse::success(results)))
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
            .route(
                "/internal/users/names",
                post(internal_resolve_users::<TestDeps>),
            )
            .route(
                "/internal/api-tokens/verify",
                post(internal_verify_api_token::<TestDeps>),
            )
            .with_state(deps)
    }

    const URI: &str = "/internal/users/00000000-0000-0000-0000-000000000001/revoke-all";
    const NAMES_URI: &str = "/internal/users/names";
    const VERIFY_URI: &str = "/internal/api-tokens/verify";

    /// The API-token verify endpoint is service-JWT-gated: no token → 401, before any DB access.
    #[tokio::test]
    async fn verify_api_token_rejects_missing_service_token() {
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(VERIFY_URI)
                    .header("content-type", "application/json")
                    .body(Body::from(
                        serde_json::json!({ "token": "pguard_a_b" }).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    /// A garbage (non-`pguard_`) token with a VALID service-JWT is rejected with a generic 401
    /// BEFORE the DB (parse fails first), proving the namespace guard + generic-401 contract.
    #[tokio::test]
    async fn verify_api_token_rejects_non_namespaced_token() {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let tok = encode_service_jwt("api-gateway", &ek, 60).unwrap();
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(VERIFY_URI)
                    .header("authorization", format!("Bearer {tok}"))
                    .header("content-type", "application/json")
                    .body(Body::from(
                        serde_json::json!({ "token": "not-a-pguard-token" }).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    fn names_body(n: usize) -> Body {
        let ids: Vec<String> = (0..n).map(|_| Uuid::new_v4().to_string()).collect();
        Body::from(serde_json::json!({ "ids": ids }).to_string())
    }

    /// The internal name-resolver is service-JWT-gated: no token → 401, before any DB access.
    #[tokio::test]
    async fn resolve_users_rejects_missing_token() {
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(NAMES_URI)
                    .header("content-type", "application/json")
                    .body(names_body(2))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    /// A valid service-JWT passes the guard; the handler then queries the (unreachable) lazy DB,
    /// so the status is NOT 401 — proving auth was accepted (mirrors the revoke-all guard test).
    #[tokio::test]
    async fn resolve_users_accepts_valid_service_token() {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let tok = encode_service_jwt("profile", &ek, 60).unwrap();
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(NAMES_URI)
                    .header("authorization", format!("Bearer {tok}"))
                    .header("content-type", "application/json")
                    .body(names_body(2))
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

    /// An over-cap batch is rejected with 400 (page it) — checked AFTER the service-JWT guard but
    /// BEFORE the DB, so the lazy pool is never touched.
    #[tokio::test]
    async fn resolve_users_rejects_over_cap_batch() {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let tok = encode_service_jwt("profile", &ek, 60).unwrap();
        let res = router()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(NAMES_URI)
                    .header("authorization", format!("Bearer {tok}"))
                    .header("content-type", "application/json")
                    .body(names_body(RESOLVE_USERS_LIMIT + 1))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::BAD_REQUEST);
    }

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
            .route(
                "/auth/register/reissue",
                post(reissue_profile_token::<RegisterTestDeps>),
            )
            .with_state(deps);
        Some((app, redis))
    }

    fn post_reissue(bearer: &str, role: &str) -> Request<Body> {
        Request::builder()
            .method("POST")
            .uri("/auth/register/reissue")
            .header("content-type", "application/json")
            .header("authorization", format!("Bearer {bearer}"))
            .body(Body::from(serde_json::json!({ "role": role }).to_string()))
            .unwrap()
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

    /// Reissue can never assign admin → 403, BEFORE any token/Redis/DB side effect.
    #[tokio::test]
    async fn reissue_rejects_admin_role() {
        let Some((app, _redis)) = register_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app.oneshot(post_reissue("x.y.z", "admin")).await.unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    /// A non-profile Bearer (here a phone-verify token) matches neither profile purpose → 401.
    /// Proves a doc-upload / access / wrong-purpose token cannot drive a role switch.
    #[tokio::test]
    async fn reissue_rejects_non_profile_token() {
        let Some((app, _redis)) = register_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let ek = EncodingKey::from_secret(USER_SECRET.as_bytes());
        let (tok, _jti) = encode_phone_verify_token("0812345678", &ek, 10).unwrap();
        let res = app.oneshot(post_reissue(&tok, "customer")).await.unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    /// Single-use regression: a signature-valid profile_token whose jti is NOT live in Redis
    /// (already consumed at `/profile/*`, or never stored) must NOT be reissuable → 401. Proves a
    /// spent profile_token can't be resurrected into a fresh one (consume-before-mutate).
    #[tokio::test]
    async fn reissue_rejects_spent_profile_token() {
        let Some((app, _redis)) = register_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let ek = EncodingKey::from_secret(USER_SECRET.as_bytes());
        // Valid signature + guard purpose, but the jti is NOT stored → GETDEL returns nil → reject
        // (BEFORE the role write, so a non-pending/absent account is never even touched).
        let (tok, _jti) =
            encode_profile_token(Uuid::new_v4(), PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        let res = app.oneshot(post_reissue(&tok, "customer")).await.unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
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

// ===================== Multi-role (Option A) HTTP tests =====================
//
// End-to-end against REAL infra (Postgres + Redis): the switch-role + enroll-role + /me + login
// surface over the concrete AppState, exercising the FULL handler (AuthUser extraction → the
// `user_roles` gate → token/profile_token mint). Gated on DATABASE_URL + a test Redis; hermetic
// SKIP when either is absent. The CRITICAL security assertion lives here: a switch to a role the
// caller is NOT enrolled in returns 409 and mints NO token.
#[cfg(test)]
mod multi_role_tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::{get, post};
    use axum::Router;
    use shared::auth::encode_jwt_with_key;
    use shared::config::{JwtConfig, ServiceJwtConfig};
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-multi-role-http-test!!";

    /// Build a real AppState wired to the given pool + redis, with HS256 keys derived from SECRET
    /// (so a token we mint here authenticates against this same state).
    fn state(db: sqlx::PgPool, redis: redis::aio::ConnectionManager) -> AppState {
        AppState {
            db,
            redis_conn: redis,
            jwt_config: JwtConfig {
                secret: SECRET.to_string(),
                expiry_minutes: 15,
                encoding_key: jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
                decoding_key: jsonwebtoken::DecodingKey::from_secret(SECRET.as_bytes()),
            },
            service_jwt_config: ServiceJwtConfig {
                encoding_key: jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
                decoding_key: jsonwebtoken::DecodingKey::from_secret(SECRET.as_bytes()),
                ttl_secs: 60,
            },
            export_client: crate::export_client::ExportClient::new(
                reqwest::Client::new(),
                jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
                60,
                vec![],
            ),
            totp_enc_key: [0u8; 32],
        }
    }

    fn router(st: AppState) -> Router {
        Router::new()
            .route("/auth/switch-role", post(switch_role))
            .route("/auth/roles", post(enroll_role))
            .route("/auth/me", get(me))
            .with_state(st)
    }

    /// Mint a real access token for `(user_id, role)` so AuthUser extraction succeeds.
    fn access_token(user_id: Uuid, role: &str) -> String {
        let ek = jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes());
        encode_jwt_with_key(user_id, role, 0, &ek, 15).unwrap().0
    }

    async fn infra() -> Option<(sqlx::PgPool, redis::aio::ConnectionManager)> {
        let db_url = std::env::var("DATABASE_URL").ok()?;
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        Some((pool, redis))
    }

    /// Seed an APPROVED user with `role` as the primary role + enrol `roles` into user_roles.
    async fn seed_user(pool: &sqlx::PgPool, primary: &str, roles: &[&str]) -> Uuid {
        let user_id = Uuid::new_v4();
        let phone = format!("0{}", &user_id.simple().to_string()[..9]);
        let pw = crate::domain::password::hash_secret("x").unwrap();
        sqlx::query(
            "INSERT INTO identity.users (id, phone, password_hash, role, approval_status) \
             VALUES ($1, $2, $3, $4::identity.user_role, 'approved'::identity.approval_status)",
        )
        .bind(user_id)
        .bind(&phone)
        .bind(&pw)
        .bind(primary)
        .execute(pool)
        .await
        .expect("seed user");
        for r in roles {
            repo::add_user_role(pool, user_id, r).await.expect("enrol");
        }
        user_id
    }

    async fn cleanup(pool: &sqlx::PgPool, user_id: Uuid) {
        let _ = sqlx::query("DELETE FROM identity.users WHERE id = $1")
            .bind(user_id)
            .execute(pool)
            .await;
    }

    fn json_post(uri: &str, bearer: &str, body: serde_json::Value) -> Request<Body> {
        Request::builder()
            .method("POST")
            .uri(uri)
            .header("authorization", format!("Bearer {bearer}"))
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .unwrap()
    }

    /// THE critical anti-escalation test: a customer-only user switching to `guard` (a role they
    /// are NOT enrolled in) gets 409 ROLE_NOT_ENROLLED and the response carries NO token (no
    /// access_token in the body, no Set-Cookie). A token is minted ONLY for an enrolled role.
    #[tokio::test]
    async fn switch_role_to_non_enrolled_is_409_and_mints_no_token() {
        let Some((pool, redis)) = infra().await else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL required");
            return;
        };
        // Customer with ONLY the customer role enrolled.
        let user_id = seed_user(&pool, "customer", &["customer"]).await;
        let app = router(state(pool.clone(), redis));
        let tok = access_token(user_id, "customer");

        let res = app
            .oneshot(json_post(
                "/auth/switch-role",
                &tok,
                serde_json::json!({ "role": "guard" }),
            ))
            .await
            .unwrap();

        assert_eq!(
            res.status(),
            StatusCode::CONFLICT,
            "switching to a non-enrolled role must be 409 (no escalation)"
        );
        assert!(
            res.headers().get(header::SET_COOKIE).is_none(),
            "a rejected switch must NOT set auth cookies"
        );
        let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(
            json["error"]["code"], "ROLE_NOT_ENROLLED",
            "the 409 carries the ROLE_NOT_ENROLLED code"
        );
        // CRUCIAL: no token of any kind is present.
        assert!(
            json["data"].get("access_token").is_none(),
            "no access token minted for a non-enrolled role"
        );

        cleanup(&pool, user_id).await;
    }

    /// A switch to an ENROLLED role mints a NEW token pair whose active role is the target — and
    /// sets the auth cookies (like login). Proves the happy path issues the right role.
    #[tokio::test]
    async fn switch_role_to_enrolled_role_mints_token_with_that_active_role() {
        let Some((pool, redis)) = infra().await else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL required");
            return;
        };
        // Dual-role user (registered as customer, also approved as guard).
        let user_id = seed_user(&pool, "customer", &["customer", "guard"]).await;
        let app = router(state(pool.clone(), redis.clone()));
        let tok = access_token(user_id, "customer");

        let res = app
            .oneshot(json_post(
                "/auth/switch-role",
                &tok,
                serde_json::json!({ "role": "guard" }),
            ))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK, "enrolled switch is 200");
        assert!(
            res.headers().get(header::SET_COOKIE).is_some(),
            "a successful switch sets auth cookies"
        );
        let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        let access = json["data"]["access_token"].as_str().expect("access token");
        // Decode the minted token; its role claim must be the switch target (guard).
        let dk = jsonwebtoken::DecodingKey::from_secret(SECRET.as_bytes());
        let claims = shared::auth::decode_jwt_with_key(access, &dk).expect("decode");
        assert_eq!(
            claims.role, "guard",
            "minted token carries the switched role"
        );
        assert_eq!(claims.sub, user_id);

        cleanup(&pool, user_id).await;
    }

    /// `GET /auth/me` returns the multi-role `roles` set alongside the single active `role`. For a
    /// dual-role user both roles appear; the active `role` is the DB primary role.
    #[tokio::test]
    async fn me_returns_the_roles_set() {
        let Some((pool, redis)) = infra().await else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL required");
            return;
        };
        let user_id = seed_user(&pool, "customer", &["customer", "guard"]).await;
        let app = router(state(pool.clone(), redis));
        let tok = access_token(user_id, "customer");

        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/auth/me")
                    .header("authorization", format!("Bearer {tok}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(
            json["data"]["role"], "customer",
            "active role is the primary"
        );
        let mut roles: Vec<String> = json["data"]["roles"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap().to_string())
            .collect();
        roles.sort();
        assert_eq!(roles, vec!["customer".to_string(), "guard".to_string()]);

        cleanup(&pool, user_id).await;
    }

    /// `POST /auth/roles` for a NEW role returns 202 + a single-use profile_token and does NOT
    /// grant the role (the role stays OUT of user_roles until approval). Re-enrolling an
    /// ALREADY-held role → 409 ROLE_ALREADY_ENROLLED.
    #[tokio::test]
    async fn enroll_role_issues_profile_token_without_granting_then_409_if_held() {
        let Some((pool, redis)) = infra().await else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL required");
            return;
        };
        // Customer-only user enrolling a guard role.
        let user_id = seed_user(&pool, "customer", &["customer"]).await;
        let app = router(state(pool.clone(), redis.clone()));
        let tok = access_token(user_id, "customer");

        let res = app
            .clone()
            .oneshot(json_post(
                "/auth/roles",
                &tok,
                serde_json::json!({ "role": "guard" }),
            ))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::ACCEPTED, "enroll returns 202");
        let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert!(
            json["data"]["profile_token"].is_string(),
            "a profile_token for the new role is returned"
        );
        assert_eq!(
            json["data"]["user_id"].as_str().unwrap(),
            user_id.to_string(),
            "the profile_token is scoped to the SAME user_id"
        );

        // The role is NOT granted yet — it must NOT be in user_roles.
        assert!(
            !repo::user_has_role(&pool, user_id, "guard").await.unwrap(),
            "enrolling does NOT grant the role until approval"
        );

        // Re-enrolling an already-held role (customer) → 409 ROLE_ALREADY_ENROLLED.
        let res2 = app
            .oneshot(json_post(
                "/auth/roles",
                &tok,
                serde_json::json!({ "role": "customer" }),
            ))
            .await
            .unwrap();
        assert_eq!(res2.status(), StatusCode::CONFLICT);
        let bytes2 = axum::body::to_bytes(res2.into_body(), usize::MAX)
            .await
            .unwrap();
        let json2: serde_json::Value = serde_json::from_slice(&bytes2).unwrap();
        assert_eq!(json2["error"]["code"], "ROLE_ALREADY_ENROLLED");

        cleanup(&pool, user_id).await;
    }

    /// Backward-compat: a single-role user's `/auth/me` returns exactly `[their_role]` and a
    /// switch to their OWN (only) role is a valid 200 (idempotent re-mint), while a switch to the
    /// other role 409s — i.e. nothing about a single-role account changed except the additive set.
    #[tokio::test]
    async fn single_role_user_is_backward_compatible() {
        let Some((pool, redis)) = infra().await else {
            eprintln!("SKIP: DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL required");
            return;
        };
        let user_id = seed_user(&pool, "guard", &["guard"]).await;
        let app = router(state(pool.clone(), redis));
        let tok = access_token(user_id, "guard");

        // /me → exactly [guard].
        let res = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/auth/me")
                    .header("authorization", format!("Bearer {tok}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(
            json["data"]["roles"].as_array().unwrap().len(),
            1,
            "a single-role user has exactly one enrolled role"
        );
        assert_eq!(json["data"]["roles"][0], "guard");

        // A switch to the OTHER (non-enrolled) role 409s — no escalation for single-role users.
        let res2 = app
            .oneshot(json_post(
                "/auth/switch-role",
                &tok,
                serde_json::json!({ "role": "customer" }),
            ))
            .await
            .unwrap();
        assert_eq!(res2.status(), StatusCode::CONFLICT);

        cleanup(&pool, user_id).await;
    }
}
