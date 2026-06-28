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
use crate::domain::{mask, registration, token};
use crate::models::{
    ChangePasswordRequest, LoginRequest, MeResponse, RefreshRequest, RegisterRequest,
    RegisterResult, ReissueProfileTokenRequest, ResolveUsersRequest, ResolvedUser, TokenPair,
    UpdateMeRequest, UserSearchQuery, UserSearchResult,
};
use crate::repo;
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
    Ok(Json(ApiResponse::success(MeResponse {
        user_id: user.user_id,
        // Prefer the freshly-read DB role (authoritative if it changed since the token issued);
        // falls back identically to the token's role in the common case.
        role: profile.role,
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
    Ok(Json(ApiResponse::success(MeResponse {
        user_id: user.user_id,
        role: profile.role,
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
            .with_state(deps)
    }

    const URI: &str = "/internal/users/00000000-0000-0000-0000-000000000001/revoke-all";
    const NAMES_URI: &str = "/internal/users/names";

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
