//! API layer — thin Axum transport handlers. No business logic beyond role gating +
//! orchestration of `domain` (pure decisions) + `repo` (DB).
//!
//! Handlers are generic over [`ProfileDeps`] so the `AuthUser` guard + the role gates are
//! unit-testable with a lightweight state (no live DB), mirroring booking's seam.

use axum::extract::{Path, Query, State};
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::{ApiResponse, ApprovalStatus};
use shared::service_jwt::ServiceCaller;

use crate::domain::mask::mask_account_number;
use crate::domain::validate;
use crate::models::{
    CustomerProfileResponse, GuardProfileResponse, InternalGuard, MyProfile, RejectRequest,
    UpsertCustomerProfileRequest, UpsertGuardProfileRequest,
};
use crate::repo;
use crate::state::{ProfileDeps, ProfileInternalDeps};

/// Hard cap on the internal catalog response. NOT paginated yet — a roster beyond this is
/// truncated (the handler logs a warn so the truncation is observable). Cursor pagination is
/// a tracked follow-up once the approved-guard count approaches this.
const INTERNAL_GUARDS_LIMIT: i64 = 100;

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

#[tracing::instrument(skip(state, req), fields(user = %user.user_id))]
pub async fn upsert_guard_profile<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<UpsertGuardProfileRequest>,
) -> Result<Json<ApiResponse<GuardProfileResponse>>, AppError> {
    require_role(&user, ROLE_GUARD)?;
    validate_guard_req(&req)?;
    // Owner read-back is masked (PDPA): a guard never needs their own full number echoed.
    let profile = repo::upsert_guard_profile(state.db(), user.user_id, &req).await?;
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

#[tracing::instrument(skip(state, req), fields(user = %user.user_id))]
pub async fn upsert_customer_profile<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<UpsertCustomerProfileRequest>,
) -> Result<Json<ApiResponse<CustomerProfileResponse>>, AppError> {
    require_role(&user, ROLE_CUSTOMER)?;
    validate::validate_text(
        req.full_name.as_deref(),
        "full_name",
        validate::MAX_TEXT_LEN,
    )
    .map_err(AppError::BadRequest)?;
    validate::validate_text(req.address.as_deref(), "address", validate::MAX_TEXT_LEN)
        .map_err(AppError::BadRequest)?;
    let profile = repo::upsert_customer_profile(state.db(), user.user_id, &req).await?;
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
    let profiles = repo::list_guard_profiles(state.db(), status).await?;
    Ok(Json(ApiResponse::success(profiles)))
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
    let guards = repo::list_approved_guards(state.db(), INTERNAL_GUARDS_LIMIT).await?;
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

// ----- POST /admin/guard-profiles/{user_id}/approve | /reject -----

#[tracing::instrument(skip(state), fields(admin = %user.user_id, target_user = %user_id))]
pub async fn admin_approve_guard<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<GuardProfileResponse>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let profile = repo::set_approval_status(state.db(), user_id, ApprovalStatus::Approved).await?;
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
    let profile = repo::set_approval_status(state.db(), user_id, ApprovalStatus::Rejected).await?;
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
        redis: redis::aio::MultiplexedConnection,
    }

    impl HasJwtSecret for TestDeps {
        fn jwt_secret(&self) -> &str {
            SECRET
        }
        fn decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
        fn redis_conn(&self) -> &redis::aio::MultiplexedConnection {
            &self.redis
        }
    }
    impl ProfileDeps for TestDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    /// Build the profile router over a lightweight test state. The `AuthUser` extractor
    /// requires `HasJwtSecret`, which mandates a real [`redis::aio::MultiplexedConnection`]
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
        let redis = redis::Client::open(redis_url)
            .ok()?
            .get_multiplexed_tokio_connection()
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
}
