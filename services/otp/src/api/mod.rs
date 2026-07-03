//! API layer — thin Axum transport handlers. No business policy beyond orchestrating
//! the Redis abuse-control flow (captcha / cooldown / daily / lockout / jti), the
//! `repo` (Postgres), the [`SmsSender`] port, and the PURE `domain` decisions.
//!
//! All three endpoints are PUBLIC (pre-auth). Outward messages are deliberately GENERIC:
//! `/otp/request` never reveals whether the phone exists, and `/otp/verify` returns the
//! same error for wrong/expired/exhausted codes (security-reviewer §3 + §9).

use axum::extract::State;
use axum::Json;
use redis::AsyncCommands;

use shared::error::AppError;
use shared::models::ApiResponse;

use crate::domain::{self, ActiveLock, LockoutDecision};
use crate::models::{
    OtpChallengeResponse, RequestOtpRequest, RequestOtpResponse, VerifyOtpRequest,
    VerifyOtpResponse,
};
use crate::repo;
use crate::state::AppState;
use crate::token::encode_phone_verify_token;

/// Captcha TTL — 3 minutes to solve (v1 parity).
const CAPTCHA_TTL_SECS: u64 = 180;
/// Daily OTP counter window (24h).
const DAILY_WINDOW_SECS: u64 = 86_400;
/// Clock-skew buffer added to the phone-verify jti's Redis TTL beyond the JWT exp.
const JTI_SKEW_BUFFER_SECS: i64 = 30;

// ----- GET /otp/challenge -----

/// Issue a math-captcha. The answer is stored in Redis (`otp_captcha:{id}`, EX 180) and
/// burned on `/otp/request` via GETDEL.
#[tracing::instrument(skip(state))]
pub async fn challenge(
    State(state): State<AppState>,
) -> Result<Json<ApiResponse<OtpChallengeResponse>>, AppError> {
    // Scope the (non-Send) ThreadRng so it is dropped before any await.
    let challenge = {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        domain::generate_captcha(rng.gen_range(1..20), rng.gen_range(1..20))
    };
    let challenge_id = uuid::Uuid::new_v4().to_string();

    let mut conn = state.redis_conn.clone();
    conn.set_ex::<_, _, ()>(
        format!("otp_captcha:{challenge_id}"),
        challenge.answer.to_string(),
        CAPTCHA_TTL_SECS,
    )
    .await?;

    Ok(Json(ApiResponse::success(OtpChallengeResponse {
        challenge_id,
        question: challenge.question,
        expires_in: CAPTCHA_TTL_SECS as i64,
    })))
}

// ----- POST /otp/request -----

/// Request an OTP. Order matters: captcha (GETDEL) → phone validation → active-lock
/// check → atomic cooldown (SET NX EX) → daily INCR (+EXPIRE recovery) → tiered-lockout
/// decision → store hashed code → send SMS. Returns a generic success either way.
#[tracing::instrument(skip(state, req), fields(has_challenge = !req.challenge_id.is_empty()))]
pub async fn request(
    State(state): State<AppState>,
    Json(req): Json<RequestOtpRequest>,
) -> Result<Json<ApiResponse<RequestOtpResponse>>, AppError> {
    let mut conn = state.redis_conn.clone();

    // 1. Validate the captcha FIRST — burns the challenge (GETDEL) before any other work
    //    so a bot can't reuse one solved challenge to spray requests.
    let expected: Option<String> = redis::cmd("GETDEL")
        .arg(format!("otp_captcha:{}", req.challenge_id))
        .query_async(&mut conn)
        .await?;
    let captcha_ok = expected
        .as_deref()
        .map(|e| e.trim() == req.answer.trim())
        .unwrap_or(false);
    if !captcha_ok {
        return Err(AppError::BadRequest(
            "รหัสยืนยันไม่ถูกต้อง กรุณาลองอีกครั้ง".to_string(),
        ));
    }

    // 2. Validate phone format (normalises to 10 digits).
    let phone = domain::validate_thai_phone(&req.phone)?;

    // 3. Active-lock check (tiered). TTL discriminates burst vs admin tier.
    let lock_key = format!("otp_lock:{phone}");
    let lock_ttl: i64 = redis::cmd("TTL")
        .arg(&lock_key)
        .query_async(&mut conn)
        .await?;
    match domain::existing_lock_decision(lock_ttl) {
        ActiveLock::None => {}
        ActiveLock::AdminContact => {
            return Err(AppError::BadRequest(
                "ขอ OTP เกินจำนวนที่กำหนด กรุณาติดต่อเจ้าหน้าที่".to_string(),
            ));
        }
        ActiveLock::Burst { remaining_minutes } => {
            return Err(AppError::BadRequest(format!(
                "ขอ OTP บ่อยเกินไป กรุณาลองใหม่ในอีก {remaining_minutes} นาที"
            )));
        }
    }

    // 4. Atomic short cooldown between consecutive requests (SET NX EX).
    let rate_key = format!("otp_rate:{phone}");
    let was_set: Option<String> = redis::cmd("SET")
        .arg(&rate_key)
        .arg("1")
        .arg("NX")
        .arg("EX")
        .arg(state.otp_config.rate_limit_seconds)
        .query_async(&mut conn)
        .await?;
    if was_set.is_none() {
        return Err(AppError::BadRequest("กรุณารอสักครู่ก่อนขอ OTP ใหม่".to_string()));
    }

    // 5. Daily per-phone counter (INCR) — also powers the tiered lockouts.
    let daily_key = format!("otp_daily:{phone}");
    let daily_count: i64 = conn.incr(&daily_key, 1).await?;
    // Ensure the 24h TTL is set (handles first-request + crash recovery) without
    // refreshing the window: only set EXPIRE when the key has no TTL (TTL < 0).
    let ttl: i64 = redis::cmd("TTL")
        .arg(&daily_key)
        .query_async(&mut conn)
        .await?;
    if ttl < 0 {
        conn.expire::<_, ()>(&daily_key, DAILY_WINDOW_SECS as i64)
            .await?;
    }

    // 5b. Short-window BURST counter (rolling BURST_WINDOW_SECS) — SEPARATE from the 24h daily cap
    //     above. The burst tier keys off THIS count, not the daily total: keying it on the daily
    //     count made a phone re-trip the 10-min lock on EVERY request for the rest of the day after
    //     just BURST_THRESHOLD requests (stuck behind a "try again in 10 minutes" message that never
    //     cleared). The short window self-resets, so a legit user recovers after one cool-off while
    //     the 24h daily cap still bounds sustained abuse. Same "set EXPIRE only when TTL < 0" rule
    //     so the window is NOT refreshed by each INCR.
    let burst_key = format!("otp_burst:{phone}");
    let burst_count: i64 = conn.incr(&burst_key, 1).await?;
    let burst_ttl: i64 = redis::cmd("TTL")
        .arg(&burst_key)
        .query_async(&mut conn)
        .await?;
    if burst_ttl < 0 {
        conn.expire::<_, ()>(&burst_key, domain::BURST_WINDOW_SECS as i64)
            .await?;
    }

    // 6. Tiered-lockout decision (PURE). Burst trips on the short-window count; admin on the daily.
    match domain::lockout_decision(
        burst_count,
        daily_count,
        state.otp_config.daily_otp_limit as i64,
    ) {
        LockoutDecision::Allow => {}
        LockoutDecision::TripAdminLock { lock_secs } => {
            conn.set_ex::<_, _, ()>(&lock_key, "1", lock_secs).await?;
            return Err(AppError::BadRequest(
                "ขอ OTP เกินจำนวนที่กำหนด กรุณาติดต่อเจ้าหน้าที่".to_string(),
            ));
        }
        LockoutDecision::TripBurstLock { lock_secs } => {
            conn.set_ex::<_, _, ()>(&lock_key, "1", lock_secs).await?;
            return Err(AppError::BadRequest(
                "ขอ OTP บ่อยเกินไป กรุณาลองใหม่ในอีก 10 นาที".to_string(),
            ));
        }
    }

    // 7. Generate the OTP, store ONLY its SHA-256 hash (never plaintext).
    let code = domain::generate_otp(state.otp_config.length);
    let code_hash = domain::sha256_hex(&code);
    let expires_at =
        chrono::Utc::now() + chrono::TimeDelta::minutes(state.otp_config.expiry_minutes);
    repo::store_code(&state.db, &phone, &code_hash, expires_at).await?;

    // 8. Send via the INET SMS port. Plaintext code never leaves this scope.
    //    On a delivery failure (transient gateway timeout / INET '08' insufficient
    //    credits / '13' disabled — all AppError::Internal) the quota+cooldown set in
    //    steps 4–5 above would otherwise stay consumed, turning a gateway hiccup into a
    //    self-DoS on the user's daily budget. Compensate (best-effort) by reverting the
    //    daily counter and clearing the short cooldown before propagating a GENERIC error.
    let message = domain::format_otp_message(&code, state.otp_config.expiry_minutes);
    let sms_phone = domain::to_international_format(&phone);
    if let Err(send_err) = state.sms.send(&sms_phone, &message).await {
        let compensation: Result<(), redis::RedisError> = redis::pipe()
            .atomic()
            .decr(&daily_key, 1)
            .decr(&burst_key, 1)
            .del(&rate_key)
            .query_async(&mut conn)
            .await;
        if let Err(comp_err) = compensation {
            // Compensation is best-effort; the keys self-expire either way. Log so the
            // residual quota/cooldown is diagnosable. Never log the phone or OTP.
            tracing::warn!(
                error = %comp_err,
                "failed to revert OTP quota/cooldown after SMS send failure"
            );
        }
        return Err(send_err);
    }

    // Generic success — does not reveal whether the phone is registered.
    Ok(Json(ApiResponse::success(RequestOtpResponse {
        message: "OTP sent successfully".to_string(),
        expires_in: state.otp_config.expiry_minutes * 60,
    })))
}

// ----- POST /otp/verify -----

/// Verify an OTP. Atomically claims the latest live code (incrementing attempts),
/// enforces max-attempts, constant-time compares the SHA-256 of the submitted code, and
/// on success marks it used + issues a single-use phone-verified JWT (jti tracked in
/// Redis for later GETDEL). All failure paths return a generic error.
#[tracing::instrument(skip(state, req))]
pub async fn verify(
    State(state): State<AppState>,
    Json(req): Json<VerifyOtpRequest>,
) -> Result<Json<ApiResponse<VerifyOtpResponse>>, AppError> {
    let phone = domain::validate_thai_phone(&req.phone)?;

    if req.code.len() != state.otp_config.length {
        return Err(AppError::BadRequest("OTP ไม่ถูกต้องหรือหมดอายุ".to_string()));
    }

    // Resolve the token purpose UP FRONT (before any Redis/DB side effect) so an unknown
    // purpose never consumes a verify attempt or burns the code. Omitted = registration —
    // the pre-purpose clients (and the register flow) send no field.
    let purpose = match req.purpose.as_deref() {
        None | Some(shared::auth::PHONE_VERIFY_PURPOSE) => shared::auth::PHONE_VERIFY_PURPOSE,
        Some(shared::auth::PIN_RESET_PURPOSE) => shared::auth::PIN_RESET_PURPOSE,
        Some(_) => {
            return Err(AppError::BadRequest("Unknown token purpose".to_string()));
        }
    };

    // Atomically find + increment-attempts on the latest live code.
    let row = repo::claim_for_verify(&state.db, &phone)
        .await?
        .ok_or_else(|| AppError::BadRequest("OTP ไม่ถูกต้องหรือหมดอายุ".to_string()))?;

    // attempts is already incremented by the claim; reject once it exceeds the cap and
    // burn the code so the user must request a fresh one.
    if row.attempts > state.otp_config.max_attempts {
        repo::mark_used(&state.db, row.id).await?;
        return Err(AppError::BadRequest(
            "เกินจำนวนครั้งที่อนุญาต กรุณาขอ OTP ใหม่".to_string(),
        ));
    }

    // Constant-time compare of sha256(submitted) vs the stored hash.
    let submitted_hash = domain::sha256_hex(&req.code);
    if !domain::hashes_match(&row.code_hash, &submitted_hash) {
        return Err(AppError::BadRequest("OTP ไม่ถูกต้อง".to_string()));
    }

    // Correct — burn the code.
    repo::mark_used(&state.db, row.id).await?;

    // Clear the abuse-control counters — the user proved ownership of this phone. Errors
    // are ignored (the state self-expires either way).
    let mut conn = state.redis_conn.clone();
    let _: Result<(), redis::RedisError> = redis::cmd("DEL")
        .arg(format!("otp_daily:{phone}"))
        .arg(format!("otp_burst:{phone}"))
        .arg(format!("otp_lock:{phone}"))
        .query_async(&mut conn)
        .await;

    // Issue the single-use phone-verified JWT scoped to the resolved purpose (carries
    // phone + jti + exp). Store the jti in Redis "valid" under the PURPOSE-scoped key
    // (with a small skew buffer) for later single-use GETDEL by the matching identity
    // route — a register token can never satisfy the reset route's marker, or vice-versa.
    let (token, jti) = encode_phone_verify_token(
        &phone,
        purpose,
        &state.jwt_config.encoding_key,
        state.otp_config.phone_verify_ttl_minutes,
    )?;
    let ttl_secs = (state.otp_config.phone_verify_ttl_minutes * 60 + JTI_SKEW_BUFFER_SECS) as u64;
    conn.set_ex::<_, _, ()>(
        shared::auth::phone_verify_jti_key(purpose, &jti),
        "valid",
        ttl_secs,
    )
    .await?;

    Ok(Json(ApiResponse::success(VerifyOtpResponse {
        phone_verified_token: token,
        expires_in: state.otp_config.phone_verify_ttl_minutes * 60,
    })))
}

#[cfg(test)]
mod tests {
    //! Router-level tests of the PUBLIC `verify` handler. The malformed-input paths
    //! (bad code length, invalid phone) reject in pure `domain` validation BEFORE any
    //! Redis/Postgres access, so they run hermetically. Building [`AppState`] requires a
    //! reconnecting `ConnectionManager`, which can only be obtained by connecting — so these are
    //! Redis-gated (skip without `TEST_REDIS_URL`/`REDIS_CACHE_URL`), matching the
    //! gated-integration pattern used across the workspace. The happy-path Redis/DB flow
    //! is covered by `repo`'s gated integration test + the pure `domain` units.
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::post;
    use axum::Router;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    use crate::config::OtpConfig;
    use crate::sms::{NoopSender, SmsSender};
    use async_trait::async_trait;
    use shared::config::JwtConfig;
    use sqlx::postgres::PgPoolOptions;

    const SECRET: &str = "test-secret-key-at-least-64-chars-long-for-testing-purposes-only!!";

    /// Fault-injecting sender: always fails the way a transient INET error does
    /// (`AppError::Internal`), to exercise `request`'s SMS-failure compensation path.
    struct FailingSender;

    #[async_trait]
    impl SmsSender for FailingSender {
        async fn send(&self, _to: &str, _text: &str) -> Result<String, AppError> {
            Err(AppError::Internal(
                "simulated SMS gateway failure".to_string(),
            ))
        }
    }

    async fn test_state(redis_conn: redis::aio::ConnectionManager) -> AppState {
        // Lazy pool to a closed port: never connects unless a handler queries. The
        // pre-IO rejection paths return before any DB use, so it stays offline.
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let jwt_config = JwtConfig {
            secret: SECRET.to_string(),
            expiry_minutes: 15,
            encoding_key: jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
            decoding_key: jsonwebtoken::DecodingKey::from_secret(SECRET.as_bytes()),
        };
        AppState {
            db,
            redis_conn,
            otp_config: OtpConfig {
                expiry_minutes: 5,
                max_attempts: 3,
                length: 6,
                rate_limit_seconds: 60,
                phone_verify_ttl_minutes: 10,
                daily_otp_limit: 10,
            },
            jwt_config,
            sms: Arc::new(NoopSender),
        }
    }

    /// Connect a real Redis if a URL is configured; otherwise `None` (test self-skips).
    async fn maybe_redis() -> Option<redis::aio::ConnectionManager> {
        let url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        shared::redis_client::create_connection_manager(&url)
            .await
            .ok()
    }

    async fn router() -> Option<Router> {
        let conn = maybe_redis().await?;
        Some(
            Router::new()
                .route("/otp/verify", post(verify))
                .with_state(test_state(conn).await),
        )
    }

    #[tokio::test]
    async fn verify_rejects_wrong_length_code_before_io() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // Wrong-length code rejects in domain validation before any DB/Redis access.
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/otp/verify")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        serde_json::json!({ "phone": "0812345678", "code": "12" }).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn verify_rejects_invalid_phone_before_io() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/otp/verify")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        serde_json::json!({ "phone": "12345", "code": "123456" }).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::BAD_REQUEST);
    }

    /// `request` must NOT consume the user's daily quota / cooldown when SMS delivery
    /// fails: the deep-review MEDIUM fix compensates (DECR otp_daily + DEL otp_rate) on a
    /// send error so a transient gateway fault is not a self-DoS on the user's budget.
    /// Gated on BOTH Redis AND Postgres — the failure happens AFTER `store_code` writes
    /// the row (step 7), so a real DB is required to reach the SMS step. Skips otherwise.
    #[tokio::test]
    async fn request_reverts_quota_and_cooldown_on_sms_failure() {
        let Some(mut conn) = maybe_redis().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let Ok(db_url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let Ok(db) = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(2))
            .connect(&db_url)
            .await
        else {
            eprintln!("SKIP: DATABASE_URL unreachable");
            return;
        };

        // Unique phone per run so daily/cooldown/lock keys start clean.
        let suffix: u32 = uuid::Uuid::new_v4().as_u128() as u32 % 1_000_000;
        let phone = format!("08{suffix:08}");
        let phone = &phone[..10];
        let daily_key = format!("otp_daily:{phone}");
        let rate_key = format!("otp_rate:{phone}");
        let lock_key = format!("otp_lock:{phone}");
        let burst_key = format!("otp_burst:{phone}");
        let _: Result<(), redis::RedisError> = redis::cmd("DEL")
            .arg(&daily_key)
            .arg(&rate_key)
            .arg(&lock_key)
            .arg(&burst_key)
            .query_async(&mut conn)
            .await;

        // Pre-solve a captcha so `request` passes step 1 (GETDEL).
        let challenge_id = uuid::Uuid::new_v4().to_string();
        conn.set_ex::<_, _, ()>(format!("otp_captcha:{challenge_id}"), "7", CAPTCHA_TTL_SECS)
            .await
            .unwrap();

        let mut state = test_state(conn.clone()).await;
        state.db = db;
        state.sms = Arc::new(FailingSender);

        let app = Router::new()
            .route("/otp/request", post(request))
            .with_state(state);

        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/otp/request")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        serde_json::json!({
                            "phone": phone,
                            "challenge_id": challenge_id,
                            "answer": "7",
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();

        // Delivery failed → generic 500 surfaced to the caller.
        assert_eq!(res.status(), StatusCode::INTERNAL_SERVER_ERROR);

        // Compensation ran: daily counter reverted (key DECRed back to 0 → DEL'd or 0)
        // and the cooldown cleared, so the user can retry immediately.
        let daily: Option<i64> = conn.get(&daily_key).await.unwrap();
        assert!(
            daily.unwrap_or(0) <= 0,
            "otp_daily must be reverted after SMS failure, got {daily:?}"
        );
        let rate_exists: bool = conn.exists(&rate_key).await.unwrap();
        assert!(
            !rate_exists,
            "otp_rate cooldown must be cleared after SMS failure"
        );
        let burst: Option<i64> = conn.get(&burst_key).await.unwrap();
        assert!(
            burst.unwrap_or(0) <= 0,
            "otp_burst must be reverted after SMS failure, got {burst:?}"
        );

        // Cleanup.
        let _: Result<(), redis::RedisError> = redis::cmd("DEL")
            .arg(&daily_key)
            .arg(&rate_key)
            .arg(&lock_key)
            .arg(&burst_key)
            .query_async(&mut conn)
            .await;
    }
}
