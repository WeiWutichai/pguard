//! API layer — thin Axum transport handlers. No business logic beyond role gating +
//! orchestration of `domain` (pure decisions) + `repo` (DB).
//!
//! Handlers are generic over [`ProfileDeps`] so the `AuthUser` guard + the role gates are
//! unit-testable with a lightweight state (no live DB), mirroring booking's seam.

use axum::extract::{FromRequestParts, Path, Query, State};
use axum::http::request::Parts;
use axum::http::HeaderMap;
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

use shared::auth::{
    decode_profile_token, AuthUser, HasJwtSecret, PROFILE_PURPOSE_CUSTOMER, PROFILE_PURPOSE_GUARD,
};
use shared::error::AppError;
use shared::models::{ApiResponse, ApprovalStatus};
use shared::service_jwt::ServiceCaller;

use crate::domain::mask::mask_account_number;
use crate::domain::validate;
use crate::models::{
    AccessAuditRow, AdminListAccessAuditQuery, CustomerProfileAdminResponse,
    CustomerProfileResponse, DocumentExpiryRow, GuardProfileResponse, InternalGuard, MyProfile,
    RecipientsQuery, RecipientsResponse, RejectRequest, UpsertCustomerProfileRequest,
    UpsertGuardProfileRequest,
};
use crate::repo;
use crate::state::{ProfileDeps, ProfileInternalDeps};

/// Hard cap on the internal catalog response. NOT paginated yet — a roster beyond this is
/// truncated (the handler logs a warn so the truncation is observable). Cursor pagination is
/// a tracked follow-up once the approved-guard count approaches this.
const INTERNAL_GUARDS_LIMIT: i64 = 100;

/// Hard cap on the broadcast-recipient response (mirrors [`INTERNAL_GUARDS_LIMIT`]). A larger
/// audience is truncated — broadcast is best-effort fan-out, not an exactly-once guarantee.
const RECIPIENTS_LIMIT: i64 = 5000;

const ROLE_GUARD: &str = "guard";
const ROLE_CUSTOMER: &str = "customer";
const ROLE_ADMIN: &str = "admin";

/// Require the caller to hold `expected_role`, else a generic 403. The message names the
/// REQUIRED role, never the caller's — no role enumeration.
fn require_role(user: &AuthUser, expected_role: &str) -> Result<(), AppError> {
    if user.role != expected_role {
        return Err(AppError::Forbidden(format!(
            "This action requires the {expected_role} role"
        )));
    }
    Ok(())
}

// ============================================================================
// Dual-auth for profile submission (profile_token OR logged-in AuthUser)
// ----------------------------------------------------------------------------
// `POST /profile/{guard,customer}` accepts EITHER a single-use, purpose-scoped
// `profile_token` (initial registration — the user is NOT logged in yet) OR a
// standard `AuthUser` (a later self-edit by a logged-in user). The resolver tries
// the profile_token first: only a token whose `purpose` matches THIS route decodes
// (purpose isolation — a guard token fails on the customer route and vice-versa),
// and it is consumed single-use via Redis GETDEL. A non-profile Bearer (an access
// token has no `purpose`) falls through to the standard `AuthUser` path, which also
// covers cookie+CSRF and the role gate. EITHER way we only learn the `user_id`;
// the profile schema is the only thing written — `users.role` (identity-owned) is
// never touched here (no cross-schema write).

/// Extract `Authorization: Bearer <token>`.
fn bearer_token(headers: &HeaderMap) -> Option<String> {
    headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer ").map(|t| t.to_string()))
}

/// Resolve the writer's `user_id` from EITHER a single-use `profile_token` of `purpose`
/// OR a logged-in `AuthUser` holding `role`. See the module note above.
async fn resolve_profile_writer<S: HasJwtSecret + Send + Sync>(
    parts: &mut Parts,
    state: &S,
    purpose: &str,
    role: &str,
) -> Result<Uuid, AppError> {
    // 1) profile_token path — only if the Bearer decodes as a profile token of THIS purpose.
    //    A wrong-purpose token does NOT decode here, so it is NOT consumed (it stays usable
    //    on its correct route) — it simply falls through to (2) and is rejected there.
    if let Some(tok) = bearer_token(&parts.headers) {
        if let Ok((user_id, jti)) = decode_profile_token(&tok, state.decoding_key(), purpose) {
            // GETDEL is the ATOMIC single-use claim (mirrors identity register): two concurrent
            // submissions of the same token → exactly one winner, the other gets nil → 401.
            // The token is consumed here in the extractor, i.e. BEFORE the repo write. A
            // transient write failure (500) therefore burns the token — the deliberate, simpler
            // trade-off (atomicity + replay-safety over retry-after-partial-failure), consistent
            // with identity register's consume-before-UPSERT. Recovery is re-OTP → re-register
            // (a still-pending phone re-registers fine and yields a fresh profile_token).
            let mut redis = state.redis_conn().clone();
            let status: Option<String> = redis::cmd("GETDEL")
                .arg(format!("profile_jti:{jti}"))
                .query_async(&mut redis)
                .await?;
            return match status.as_deref() {
                Some("valid") => Ok(user_id),
                _ => Err(AppError::Unauthorized(
                    "Profile token is invalid, expired, or already used".to_string(),
                )),
            };
        }
    }
    // 2) logged-in user path — standard AuthUser (Bearer or cookie + CSRF + revocation),
    //    role-gated. A non-profile Bearer / cookie / wrong-role all resolve here.
    let user = AuthUser::from_request_parts(parts, state).await?;
    if user.role != role {
        return Err(AppError::Forbidden(format!(
            "This action requires the {role} role"
        )));
    }
    Ok(user.user_id)
}

/// Authorized writer of a GUARD profile: a `guard_profile` token OR a logged-in guard.
pub struct GuardProfileWriter {
    pub user_id: Uuid,
}

impl<S> FromRequestParts<S> for GuardProfileWriter
where
    S: HasJwtSecret + Send + Sync,
{
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let user_id =
            resolve_profile_writer(parts, state, PROFILE_PURPOSE_GUARD, ROLE_GUARD).await?;
        Ok(Self { user_id })
    }
}

/// Authorized writer of a CUSTOMER profile: a `customer_profile` token OR a logged-in customer.
pub struct CustomerProfileWriter {
    pub user_id: Uuid,
}

impl<S> FromRequestParts<S> for CustomerProfileWriter
where
    S: HasJwtSecret + Send + Sync,
{
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let user_id =
            resolve_profile_writer(parts, state, PROFILE_PURPOSE_CUSTOMER, ROLE_CUSTOMER).await?;
        Ok(Self { user_id })
    }
}

/// Apply the shared field validators to a guard-profile write. Maps the pure validators'
/// `String` errors to `BadRequest`.
fn validate_guard_req(req: &UpsertGuardProfileRequest) -> Result<(), AppError> {
    validate::validate_years_of_experience(req.years_of_experience)
        .map_err(AppError::BadRequest)?;
    validate::validate_text(req.gender.as_deref(), "gender", validate::MAX_TEXT_LEN)
        .map_err(AppError::BadRequest)?;
    validate::validate_text(
        req.previous_workplace.as_deref(),
        "previous_workplace",
        validate::MAX_TEXT_LEN,
    )
    .map_err(AppError::BadRequest)?;
    validate::validate_text(
        req.bank_name.as_deref(),
        "bank_name",
        validate::MAX_TEXT_LEN,
    )
    .map_err(AppError::BadRequest)?;
    validate::validate_text(
        req.account_name.as_deref(),
        "account_name",
        validate::MAX_TEXT_LEN,
    )
    .map_err(AppError::BadRequest)?;
    validate::validate_text(
        req.account_number.as_deref(),
        "account_number",
        validate::MAX_ACCOUNT_NUMBER_LEN,
    )
    .map_err(AppError::BadRequest)?;
    Ok(())
}

/// Mask a guard profile's account number IN PLACE for an owner-facing read (PDPA). Admin
/// reads skip this and return the full value.
fn mask_guard_response(mut profile: GuardProfileResponse) -> GuardProfileResponse {
    profile.account_number = profile.account_number.as_deref().map(mask_account_number);
    profile
}

// ----- POST /profile/guard — upsert own guard profile -----

#[tracing::instrument(skip(state, writer, req), fields(user = %writer.user_id))]
pub async fn upsert_guard_profile<S: ProfileDeps>(
    State(state): State<S>,
    writer: GuardProfileWriter,
    Json(req): Json<UpsertGuardProfileRequest>,
) -> Result<Json<ApiResponse<GuardProfileResponse>>, AppError> {
    validate_guard_req(&req)?;
    // Writes ONLY the profile schema (approval_status defaults to 'pending'); identity owns
    // the account role/state and is never touched here. Owner read-back is masked (PDPA).
    let profile = repo::upsert_guard_profile(state.db(), writer.user_id, &req).await?;
    Ok(Json(ApiResponse::success(mask_guard_response(profile))))
}

// ----- PUT /profile/guard — update own guard profile -----

#[tracing::instrument(skip(state, req), fields(user = %user.user_id))]
pub async fn update_guard_profile<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<UpsertGuardProfileRequest>,
) -> Result<Json<ApiResponse<GuardProfileResponse>>, AppError> {
    require_role(&user, ROLE_GUARD)?;
    validate_guard_req(&req)?;
    let profile = repo::update_guard_profile(state.db(), user.user_id, &req).await?;
    Ok(Json(ApiResponse::success(mask_guard_response(profile))))
}

// ----- POST /profile/customer — upsert own customer profile -----

#[tracing::instrument(skip(state, writer, req), fields(user = %writer.user_id))]
pub async fn upsert_customer_profile<S: ProfileDeps>(
    State(state): State<S>,
    writer: CustomerProfileWriter,
    Json(req): Json<UpsertCustomerProfileRequest>,
) -> Result<Json<ApiResponse<CustomerProfileResponse>>, AppError> {
    validate::validate_text(
        req.full_name.as_deref(),
        "full_name",
        validate::MAX_TEXT_LEN,
    )
    .map_err(AppError::BadRequest)?;
    validate::validate_text(req.address.as_deref(), "address", validate::MAX_TEXT_LEN)
        .map_err(AppError::BadRequest)?;
    // Writes ONLY the customer profile schema — never identity's. The FIRST creation also
    // emits `user.approved` (outbox, same tx in repo): customers are auto-approved on their
    // first profile submission and identity flips its own approval_status on consume. Guards
    // keep the admin-review path (`/admin/guard-profiles/{id}/approve`).
    let profile = repo::upsert_customer_profile(state.db(), writer.user_id, &req).await?;
    Ok(Json(ApiResponse::success(profile)))
}

// ----- GET /profile/me — the caller's own profile (account number MASKED) -----

#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn get_my_profile<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<MyProfile>>, AppError> {
    // A guard sees their guard profile (masked); a customer sees their customer profile.
    // Admins have no self-profile in this slice → 404 (they manage others, not self).
    match user.role.as_str() {
        ROLE_GUARD => {
            let profile = repo::get_guard_profile(state.db(), user.user_id)
                .await?
                .ok_or_else(|| AppError::NotFound("Profile not found".to_string()))?;
            Ok(Json(ApiResponse::success(MyProfile::Guard(
                mask_guard_response(profile),
            ))))
        }
        ROLE_CUSTOMER => {
            let profile = repo::get_customer_profile(state.db(), user.user_id)
                .await?
                .ok_or_else(|| AppError::NotFound("Profile not found".to_string()))?;
            Ok(Json(ApiResponse::success(MyProfile::Customer(profile))))
        }
        _ => Err(AppError::NotFound("Profile not found".to_string())),
    }
}

// ----- GET /admin/guard-profiles?approval_status=... — admin list (FULL bank) -----

#[derive(Debug, Deserialize)]
pub struct ListQuery {
    /// Optional filter: pending | approved | rejected. An unknown value → 400.
    pub approval_status: Option<String>,
}

#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_list_guard_profiles<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> Result<Json<ApiResponse<Vec<GuardProfileResponse>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let status = match q.approval_status.as_deref() {
        None => None,
        Some(s) => Some(
            s.parse::<ApprovalStatus>()
                .map_err(|_| AppError::BadRequest("invalid approval_status filter".to_string()))?,
        ),
    };
    // Admin sees the FULL account number (not masked) — onboarding review needs it.
    // List read → replica (C5.3); the §30 read-audit below is a WRITE → primary.
    let profiles = repo::list_guard_profiles(state.db_read(), status).await?;
    // PDPA §30: record this admin read of personal data (who accessed what).
    repo::record_access(
        state.db(),
        user.user_id,
        "admin_list_guard_profiles",
        q.approval_status.as_deref(),
    )
    .await?;
    Ok(Json(ApiResponse::success(profiles)))
}

// ----- GET /admin/customer-profiles — admin list (cross-user) -----

/// List every customer profile for the admin surface. Admin-only (the edge proves identity,
/// not role — authz is this service's job). No filter param: customer approval is not stored
/// in profile (it lives in identity; customers auto-approve on first profile insert), so a
/// `?approval_status` filter would be meaningless against this table — see the guard list for
/// the filtered variant. Mirrors [`admin_list_guard_profiles`]: list read on the replica
/// (C5.3), PDPA §30 read-audit WRITE on the primary. No masking — customer profiles hold no
/// bank field (`full_name`/`address` are the only PII, returned as-is like the owner read).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_list_customer_profiles<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<CustomerProfileAdminResponse>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let profiles = repo::list_customer_profiles(state.db_read()).await?;
    // PDPA §30: record this admin read of personal data (who accessed what). No filter to log.
    repo::record_access(
        state.db(),
        user.user_id,
        "admin_list_customer_profiles",
        None,
    )
    .await?;
    Ok(Json(ApiResponse::success(profiles)))
}

// ----- GET /admin/access-audit — PDPA §30 data-access audit log (admin) -----

/// List the data-access audit trail (admin). Admin-only. Optional `action` filter + limit/offset,
/// newest first; read from the replica. NOTE: this is the §30 access trail (who read what PII),
/// NOT a full business-action feed — the design's broader "activity" stream (approved/refund/
/// check-in events with actor/IP/payload) would need a dedicated audit-event sink (out of scope).
/// Reading the audit log is itself NOT audited (it would recurse).
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn admin_list_access_audit<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<AdminListAccessAuditQuery>,
) -> Result<Json<ApiResponse<Vec<AccessAuditRow>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let rows = repo::list_access_audit(state.db_read(), q.action.as_deref(), limit, offset).await?;
    Ok(Json(ApiResponse::success(rows)))
}

// ----- GET /internal/guards (service-to-service catalog) -----

/// Internal read used by booking's discovery (`/available-guards`) to list the APPROVED
/// guard catalog. Guarded by [`ServiceCaller`] (a valid service-JWT) — never reachable from
/// the public edge (the gateway blocks `/internal/`). Returns only `{ user_id,
/// years_of_experience }` (least-privilege — no bank/PII over the wire). Generic over
/// [`ProfileInternalDeps`] so the guard is unit-testable (mirrors booking's internal read).
#[tracing::instrument(skip(state), fields(caller = %caller.service))]
pub async fn internal_list_guards<S: ProfileInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
) -> Result<Json<ApiResponse<Vec<InternalGuard>>>, AppError> {
    let guards = repo::list_approved_guards(state.db_read(), INTERNAL_GUARDS_LIMIT).await?;
    // Surface the (un-paginated) truncation so a roster that outgrows the cap is observable
    // rather than silently dropping guards from discovery.
    if guards.len() as i64 >= INTERNAL_GUARDS_LIMIT {
        tracing::warn!(
            limit = INTERNAL_GUARDS_LIMIT,
            "approved-guard catalog hit the cap; discovery results truncated (no pagination yet)"
        );
    }
    Ok(Json(ApiResponse::success(guards)))
}

// ----- GET /internal/users/{user_id}/export (PDPA §19/§32 data export) -----

/// Export the user's OWN profile data for a cross-service data export. `ServiceCaller`-gated
/// (only identity's aggregator, holding a valid service-JWT, reaches this) and scoped
/// strictly to the path `user_id`, so it can never return another user's rows.
#[tracing::instrument(skip(state), fields(caller = %caller.service, user = %user_id))]
pub async fn internal_export_user<S: ProfileInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let data = repo::export_user_data(state.db_read(), user_id).await?;
    Ok(Json(ApiResponse::success(data)))
}

/// Horizon for the expiring-documents surface: include docs expiring within ~90 days (plus any
/// already expired). The client buckets into expired / 7 / 30 / 90.
const DOC_EXPIRY_HORIZON_DAYS: i64 = 90;

// ----- GET /admin/documents/expiring — guard documents needing renewal (admin) -----

/// List guard documents expiring within the horizon (incl. already-expired), soonest first.
/// Admin only (else 403); replica read. NOTE: the document-upload + expiry-CAPTURE flow is a
/// deferred follow-up, so this returns nothing until that lands — the schema, endpoint, and
/// screen are real and ready, but never fabricate rows.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_list_expiring_documents<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<DocumentExpiryRow>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let rows = repo::list_expiring_documents(state.db_read(), DOC_EXPIRY_HORIZON_DAYS).await?;
    Ok(Json(ApiResponse::success(rows)))
}

// ----- GET /internal/profiles/recipients (broadcast audience for notification) -----

/// Resolve the `user_id`s for a broadcast audience (`all|guards|customers`). `ServiceCaller`-
/// gated (only notification's bulk-send, holding a valid service-JWT, reaches this — the
/// gateway blocks `/internal/`). notification owns no user/role registry, so it asks profile
/// (which owns the guard/customer profile tables). Least-privilege — returns only `user_id`s,
/// never names/PII. Bounded by [`RECIPIENTS_LIMIT`]; a larger roster is truncated (logged).
#[tracing::instrument(skip(state), fields(caller = %caller.service))]
pub async fn internal_list_recipients<S: ProfileInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Query(q): Query<RecipientsQuery>,
) -> Result<Json<ApiResponse<RecipientsResponse>>, AppError> {
    let audience = match q.audience.as_str() {
        "all" | "guards" | "customers" => q.audience.clone(),
        other => {
            return Err(AppError::BadRequest(format!(
                "audience must be all|guards|customers (got {other})"
            )))
        }
    };
    let user_ids = repo::recipient_ids(state.db_read(), &audience, RECIPIENTS_LIMIT).await?;
    if user_ids.len() as i64 >= RECIPIENTS_LIMIT {
        tracing::warn!(
            limit = RECIPIENTS_LIMIT,
            %audience,
            "broadcast recipient roster hit the cap; audience truncated (no pagination yet)"
        );
    }
    Ok(Json(ApiResponse::success(RecipientsResponse {
        count: user_ids.len() as i64,
        audience,
        user_ids,
    })))
}

// ----- POST /admin/guard-profiles/{user_id}/approve | /reject -----

#[tracing::instrument(skip(state), fields(admin = %user.user_id, target_user = %user_id))]
pub async fn admin_approve_guard<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<GuardProfileResponse>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    // The approve emits `user.approved` atomically (outbox) → identity flips its own
    // `users.approval_status` so the guard can finally log in. `role = guard` (this route).
    let profile =
        repo::set_approval_status(state.db(), user_id, ApprovalStatus::Approved, ROLE_GUARD)
            .await?;
    Ok(Json(ApiResponse::success(profile)))
}

#[tracing::instrument(skip(state, body), fields(admin = %user.user_id, target_user = %user_id))]
pub async fn admin_reject_guard<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
    body: Option<Json<RejectRequest>>,
) -> Result<Json<ApiResponse<GuardProfileResponse>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    if let Some(Json(RejectRequest { reason: Some(r) })) = &body {
        // Reason is contextual metadata, not PII — safe to log; persisting it is a follow-up.
        tracing::info!(reason = %r, "guard profile rejected with reason");
    }
    let profile =
        repo::set_approval_status(state.db(), user_id, ApprovalStatus::Rejected, ROLE_GUARD)
            .await?;
    Ok(Json(ApiResponse::success(profile)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::{get, post, put};
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-profile-test!!!";

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::ConnectionManager,
    }

    impl HasJwtSecret for TestDeps {
        fn jwt_secret(&self) -> &str {
            SECRET
        }
        fn decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
        fn redis_conn(&self) -> &redis::aio::ConnectionManager {
            &self.redis
        }
    }
    impl ProfileDeps for TestDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    /// Build the profile router over a lightweight test state. The `AuthUser` extractor
    /// requires `HasJwtSecret`, which mandates a real [`redis::aio::ConnectionManager`]
    /// for the jti revocation blocklist — there is no public way to construct one without
    /// connecting. So, exactly like booking's router tests, these are hermetic by default
    /// and only run when a test Redis is provided via `TEST_REDIS_URL` (falling back to
    /// `REDIS_CACHE_URL`). Returns `None` → the caller SKIPs.
    ///
    /// Auth-reject and role-gate paths short-circuit before any DB access, so the lazy pool
    /// to a closed port is never connected (a wrong-role 403 fails at `require_role`, a
    /// missing/invalid token 401 fails at the extractor — both before `repo`).
    async fn router() -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db,
            redis,
        };
        Some(
            Router::new()
                .route("/profile/guard", post(upsert_guard_profile::<TestDeps>))
                .route("/profile/guard", put(update_guard_profile::<TestDeps>))
                .route(
                    "/profile/customer",
                    post(upsert_customer_profile::<TestDeps>),
                )
                .route("/profile/me", get(get_my_profile::<TestDeps>))
                .route(
                    "/admin/guard-profiles",
                    get(admin_list_guard_profiles::<TestDeps>),
                )
                .route(
                    "/admin/customer-profiles",
                    get(admin_list_customer_profiles::<TestDeps>),
                )
                .route(
                    "/admin/access-audit",
                    get(admin_list_access_audit::<TestDeps>),
                )
                .route(
                    "/admin/documents/expiring",
                    get(admin_list_expiring_documents::<TestDeps>),
                )
                .route(
                    "/admin/guard-profiles/{user_id}/approve",
                    post(admin_approve_guard::<TestDeps>),
                )
                .route(
                    "/admin/guard-profiles/{user_id}/reject",
                    post(admin_reject_guard::<TestDeps>),
                )
                .with_state(deps),
        )
    }

    fn token(role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _) = encode_jwt_with_key(Uuid::new_v4(), role, 0, &ek, 60).unwrap();
        tok
    }

    fn guard_body() -> Body {
        Body::from(serde_json::json!({ "gender": "male" }).to_string())
    }

    // ----- 401: missing / invalid token -----

    #[tokio::test]
    async fn upsert_guard_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/profile/guard")
                    .header("content-type", "application/json")
                    .body(guard_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn upsert_guard_rejects_invalid_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/profile/guard")
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .header("content-type", "application/json")
                    .body(guard_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn me_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/profile/me")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    // ----- 403: wrong-role token hits the role gate (before any DB access) -----

    #[tokio::test]
    async fn upsert_guard_rejects_customer_role() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/profile/guard")
                    .header("authorization", format!("Bearer {}", token(ROLE_CUSTOMER)))
                    .header("content-type", "application/json")
                    .body(guard_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a customer must not upsert a guard profile"
        );
    }

    #[tokio::test]
    async fn admin_list_rejects_guard_role() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/guard-profiles")
                    .header("authorization", format!("Bearer {}", token(ROLE_GUARD)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a guard must not list the admin onboarding queue"
        );
    }

    #[tokio::test]
    async fn admin_access_audit_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard must not read the data-access audit trail.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/access-audit")
                    .header("authorization", format!("Bearer {}", token(ROLE_GUARD)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_list_customers_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer (not admin) must not list every customer's PII (name/address).
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/customer-profiles")
                    .header("authorization", format!("Bearer {}", token(ROLE_CUSTOMER)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a customer must not list the admin customer directory"
        );
    }

    #[tokio::test]
    async fn admin_expiring_docs_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard must not read the cross-user expiring-documents surface.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/documents/expiring")
                    .header("authorization", format!("Bearer {}", token(ROLE_GUARD)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_approve_rejects_guard_role() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/admin/guard-profiles/{id}/approve"))
                    .header("authorization", format!("Bearer {}", token(ROLE_GUARD)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    // ----- dual-auth: single-use, purpose-isolated profile_token -----

    use redis::AsyncCommands;
    use shared::auth::{encode_profile_token, PROFILE_PURPOSE_GUARD};

    /// Router (guard + customer POST routes) plus the live Redis conn, so the profile_token
    /// tests can seed/inspect the single-use `profile_jti` marker. Redis-gated like `router()`.
    async fn token_router() -> Option<(Router, redis::aio::ConnectionManager)> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db,
            redis: redis.clone(),
        };
        let app = Router::new()
            .route("/profile/guard", post(upsert_guard_profile::<TestDeps>))
            .route(
                "/profile/customer",
                post(upsert_customer_profile::<TestDeps>),
            )
            .with_state(deps);
        Some((app, redis))
    }

    fn post_with_bearer(uri: &str, token: &str, body: Body) -> Request<Body> {
        Request::builder()
            .method("POST")
            .uri(uri)
            .header("authorization", format!("Bearer {token}"))
            .header("content-type", "application/json")
            .body(body)
            .unwrap()
    }

    fn customer_body() -> Body {
        Body::from(serde_json::json!({ "full_name": "Somchai" }).to_string())
    }

    /// A valid `guard_profile` token authorizes the guard route (NOT 401/403 — it reaches the
    /// repo, which 500s on the closed lazy pool) and is single-use: the second presentation is
    /// rejected 401 (the jti was consumed via GETDEL). NB this also documents the deliberate
    /// consume-on-extract trade-off — the first call's repo write FAILED (500) yet the token is
    /// still burned, so reuse 401s (atomicity over retry-after-partial-failure; see the resolver).
    #[tokio::test]
    async fn guard_profile_token_is_accepted_and_single_use() {
        let Some((app, mut redis)) = token_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, jti) =
            encode_profile_token(Uuid::new_v4(), PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        let _: () = redis
            .set_ex(format!("profile_jti:{jti}"), "valid", 600)
            .await
            .expect("seed jti");

        let res = app
            .clone()
            .oneshot(post_with_bearer("/profile/guard", &tok, guard_body()))
            .await
            .unwrap();
        assert_ne!(
            res.status(),
            StatusCode::UNAUTHORIZED,
            "valid token must pass auth"
        );
        assert_ne!(
            res.status(),
            StatusCode::FORBIDDEN,
            "purpose grants the route"
        );

        // Second use of the same token → jti already consumed → 401.
        let res2 = app
            .oneshot(post_with_bearer("/profile/guard", &tok, guard_body()))
            .await
            .unwrap();
        assert_eq!(
            res2.status(),
            StatusCode::UNAUTHORIZED,
            "profile_token is single-use"
        );
    }

    /// Purpose isolation: a `guard_profile` token on the CUSTOMER route is rejected (401), and
    /// crucially the token is NOT consumed — it must remain usable on its correct guard route.
    #[tokio::test]
    async fn guard_profile_token_rejected_on_customer_route_and_not_consumed() {
        let Some((app, mut redis)) = token_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, jti) =
            encode_profile_token(Uuid::new_v4(), PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        let key = format!("profile_jti:{jti}");
        let _: () = redis.set_ex(&key, "valid", 600).await.expect("seed jti");

        let res = app
            .oneshot(post_with_bearer("/profile/customer", &tok, customer_body()))
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::UNAUTHORIZED,
            "a guard token must not authorize the customer route"
        );

        // The token must still be live (purpose mismatch does not burn it).
        let still_valid: bool = redis.exists(&key).await.expect("exists check");
        assert!(
            still_valid,
            "a purpose-mismatched token must NOT be consumed"
        );
        let _: () = redis.del(&key).await.unwrap_or(());
    }

    /// End-to-end boundary proof (DATABASE_URL + Redis): a guard submits their profile with a
    /// `profile_token` (NOT logged in) — the guard_profiles row is written, while the
    /// identity-owned `identity.users.role` is left untouched (no cross-schema write). Gated on
    /// both a real Postgres (identity 0001+0003 + profile 0001 migrated) and a test Redis.
    #[tokio::test]
    async fn profile_token_writes_profile_but_not_identity_role() {
        let Ok(db_url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL required for the boundary test");
            return;
        };
        let Ok(redis_url) =
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL"))
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
            .expect("connect Postgres");
        let mut redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .expect("redis conn");

        // Seed an identity user (role=guard, pending) — as identity's register would.
        let uid = Uuid::new_v4();
        let phone: String = format!(
            "0{}",
            uid.simple()
                .to_string()
                .chars()
                .filter(|c| c.is_ascii_digit())
                .take(9)
                .collect::<String>()
        );
        sqlx::query(
            "INSERT INTO identity.users (id, phone, password_hash, role, approval_status) \
             VALUES ($1, $2, 'x', 'guard', 'pending'::identity.approval_status)",
        )
        .bind(uid)
        .bind(&phone)
        .execute(&pool)
        .await
        .expect("seed identity user");

        // Router over the REAL pool; issue + seed a single-use guard profile_token.
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db: pool.clone(),
            redis: redis.clone(),
        };
        let app = Router::new()
            .route("/profile/guard", post(upsert_guard_profile::<TestDeps>))
            .with_state(deps);
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, jti) = encode_profile_token(uid, PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        let _: () = redis
            .set_ex(format!("profile_jti:{jti}"), "valid", 600)
            .await
            .expect("seed jti");

        let res = app
            .oneshot(post_with_bearer(
                "/profile/guard",
                &tok,
                Body::from(serde_json::json!({ "years_of_experience": 3 }).to_string()),
            ))
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::OK,
            "profile_token submission succeeds"
        );

        // The profile row was written...
        let (count,): (i64,) = sqlx::query_as(
            "SELECT count(*)::bigint FROM profile.guard_profiles WHERE user_id = $1",
        )
        .bind(uid)
        .fetch_one(&pool)
        .await
        .expect("count profile");
        assert_eq!(count, 1, "guard profile written");

        // ...and the identity-owned role is UNCHANGED (no cross-schema write).
        let (role,): (String,) =
            sqlx::query_as("SELECT role::text FROM identity.users WHERE id = $1")
                .bind(uid)
                .fetch_one(&pool)
                .await
                .expect("read role");
        assert_eq!(role, "guard", "profile must NOT touch identity.users.role");

        // cleanup
        let _ = sqlx::query("DELETE FROM profile.guard_profiles WHERE user_id = $1")
            .bind(uid)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM identity.users WHERE id = $1")
            .bind(uid)
            .execute(&pool)
            .await;
    }

    // ----- internal guard catalog: service-JWT guard (no Redis/DB needed) -----

    const SERVICE_SECRET: &str =
        "service-secret-at-least-64-characters-long-for-internal-hs256-test!!";

    #[derive(Clone)]
    struct InternalDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
    }
    impl shared::service_jwt::HasServiceJwt for InternalDeps {
        fn service_decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
    }
    impl ProfileInternalDeps for InternalDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    /// Internal router over a lightweight state. The `ServiceCaller` extractor only needs the
    /// service decoding key — no Redis, no live DB. Rejected requests short-circuit at the
    /// guard before any DB access (mirrors booking's internal_router test).
    fn internal_router() -> Router {
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = InternalDeps {
            dec: Arc::new(DecodingKey::from_secret(SERVICE_SECRET.as_bytes())),
            db,
        };
        Router::new()
            .route(
                "/internal/guards",
                get(internal_list_guards::<InternalDeps>),
            )
            .route(
                "/internal/profiles/recipients",
                get(internal_list_recipients::<InternalDeps>),
            )
            .with_state(deps)
    }

    #[tokio::test]
    async fn internal_guards_rejects_missing_token() {
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/internal/guards")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_guards_rejects_invalid_token() {
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/internal/guards")
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_guards_accepts_valid_service_token() {
        // A valid service-JWT (as minted by booking) must pass the guard; the handler then
        // queries the (unreachable) DB, so the response is NOT 401 — proving auth passed.
        use shared::service_jwt::encode_service_jwt;
        let ek = EncodingKey::from_secret(SERVICE_SECRET.as_bytes());
        let tok = encode_service_jwt("booking", &ek, 60).unwrap();
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/internal/guards")
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

    // ----- internal broadcast-recipients: service-JWT guard (no Redis/DB needed) -----

    #[tokio::test]
    async fn internal_recipients_rejects_missing_token() {
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/internal/profiles/recipients?audience=guards")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_recipients_accepts_valid_service_token() {
        // A valid service-JWT (as minted by notification) must pass the guard; the handler then
        // queries the (unreachable) DB, so the response is NOT 401 — proving auth passed.
        use shared::service_jwt::encode_service_jwt;
        let ek = EncodingKey::from_secret(SERVICE_SECRET.as_bytes());
        let tok = encode_service_jwt("notification", &ek, 60).unwrap();
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/internal/profiles/recipients?audience=all")
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
