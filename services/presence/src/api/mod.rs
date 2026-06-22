//! API layer — thin Axum transport: the IDOR-safe REST reads + the WS ingress module. No
//! business logic beyond authz gating + orchestrating `repo` (DB) and `domain` (the pure
//! freshness rule). Handlers are generic over [`PresenceDeps`] so the role gate + IDOR authz
//! are unit-testable with a lightweight state (no DB), mirroring calling/payment.

pub mod ws;

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::Utc;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::domain;
use crate::models::{
    GuardLocation, GuardLocationRow, HistoryPoint, HistoryQuery, LocationsQuery, OnlineGuards,
};
use crate::repo;
use crate::state::{BookingAuthz, PresenceDeps, PresenceInternalDeps};

/// GET /locations — bulk live guard locations. **Admin only** (a customer can NEVER pull bulk).
#[tracing::instrument(skip(state), fields(user = %user.user_id, role = %user.role))]
pub async fn list_locations<S: PresenceDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<LocationsQuery>,
) -> Result<Json<ApiResponse<Vec<GuardLocation>>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "Only admins can access bulk location data".to_string(),
        ));
    }
    let now = Utc::now();
    // Heavy admin bulk read → read replica (C5.3); falls back to primary when unset.
    let locations = repo::list_locations(state.db_read(), q.online_only)
        .await?
        .into_iter()
        .map(|row| to_location(row, now))
        .collect();
    Ok(Json(ApiResponse::success(locations)))
}

/// GET /guards/{id}/location — a guard's latest position. IDOR-gated (own / active-booking
/// customer / admin).
#[tracing::instrument(skip(state), fields(user = %user.user_id, role = %user.role, guard_id = %id))]
pub async fn guard_location<S: PresenceDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<GuardLocation>>, AppError> {
    authorize_guard_read(&state, &user, id).await?;
    let row = repo::latest_location(state.db(), id).await?;
    Ok(Json(ApiResponse::success(to_location(row, Utc::now()))))
}

/// GET /guards/{id}/history — a guard's GPS history (newest first). Same IDOR gate.
#[tracing::instrument(skip(state), fields(user = %user.user_id, role = %user.role, guard_id = %id))]
pub async fn guard_history<S: PresenceDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Query(q): Query<HistoryQuery>,
) -> Result<Json<ApiResponse<Vec<HistoryPoint>>>, AppError> {
    authorize_guard_read(&state, &user, id).await?;
    // Heavy paginated history read → read replica (C5.3); the authz gate above ran first.
    let history = repo::history(state.db_read(), id, q.limit, q.offset)
        .await?
        .into_iter()
        .map(HistoryPoint::from)
        .collect();
    Ok(Json(ApiResponse::success(history)))
}

/// GET /internal/online-guards — the ids of guards who are currently LIVE (`is_online` AND a
/// fresh fix; [`domain::is_live`]). Service-JWT'd ([`ServiceCaller`]) — never reachable from the
/// public edge (the gateway blocks `/internal/`). Consumed by booking's `/available-guards`
/// discovery to drop OFFLINE approved guards from the customer list ("พร้อมรับงาน" filter).
///
/// Returns ONLY ids — no lat/lng/PII (unlike the admin `/locations` bulk read), so the discovery
/// consult is least-privilege. The freshness window is presence's own [`domain::FRESHNESS_MINUTES`]
/// rule applied in SQL, so callers always see the same "live" definition as the admin map.
#[tracing::instrument(skip(state), fields(caller = %caller.service))]
pub async fn internal_online_guards<S: PresenceInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
) -> Result<Json<ApiResponse<OnlineGuards>>, AppError> {
    let guard_ids =
        repo::online_guard_ids(state.db(), Utc::now(), domain::FRESHNESS_MINUTES).await?;
    Ok(Json(ApiResponse::success(OnlineGuards { guard_ids })))
}

/// The IDOR rule for a per-guard read: an admin may read any guard; a guard only its own; a
/// customer only a guard they have an ACTIVE booking with (else 403 — no probing unrelated
/// guards). The customer check hits the event-derived read-model via the `BookingAuthz` seam.
async fn authorize_guard_read<S: PresenceDeps>(
    state: &S,
    user: &AuthUser,
    guard_id: Uuid,
) -> Result<(), AppError> {
    match user.role.as_str() {
        "admin" => Ok(()),
        "guard" => {
            if user.user_id == guard_id {
                Ok(())
            } else {
                Err(AppError::Forbidden(
                    "Guards can only read their own location".to_string(),
                ))
            }
        }
        "customer" => {
            if state
                .booking_authz()
                .has_active_booking(user.user_id, guard_id)
                .await?
            {
                Ok(())
            } else {
                Err(AppError::Forbidden(
                    "You can only track a guard assigned to your active booking".to_string(),
                ))
            }
        }
        _ => Err(AppError::Forbidden("Not authorized".to_string())),
    }
}

/// Assemble the response DTO, computing `is_live` (the 5-minute discovery freshness rule) from
/// the stored `is_online` + `recorded_at` at read time.
fn to_location(row: GuardLocationRow, now: chrono::DateTime<Utc>) -> GuardLocation {
    GuardLocation {
        is_live: domain::is_live(row.is_online, row.recorded_at, now),
        guard_id: row.guard_id,
        lat: row.lat,
        lng: row.lng,
        accuracy: row.accuracy,
        heading: row.heading,
        speed: row.speed,
        recorded_at: row.recorded_at,
        is_online: row.is_online,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::{BookingAuthz, PresenceDeps};
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::get;
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str =
        "user-secret-at-least-64-characters-long-for-the-hs256-presence-rest-test!";

    /// Stub the IDOR read-model: `allow` is what `has_active_booking` returns.
    #[derive(Clone)]
    struct StubAuthz {
        allow: bool,
    }
    impl BookingAuthz for StubAuthz {
        async fn has_active_booking(&self, _c: Uuid, _g: Uuid) -> Result<bool, AppError> {
            Ok(self.allow)
        }
    }

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::ConnectionManager,
        authz: StubAuthz,
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
    impl PresenceDeps for TestDeps {
        type Authz = StubAuthz;
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn booking_authz(&self) -> &StubAuthz {
            &self.authz
        }
        fn redis_pub(&self) -> &redis::aio::ConnectionManager {
            &self.redis
        }
    }

    async fn router(allow_booking: bool) -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        // A lazy pool to an invalid DB: authz failures return BEFORE any query (hermetic); a
        // request that PASSES authz then fails at the DB (≠ 403), which is what we assert.
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db,
            redis,
            authz: StubAuthz {
                allow: allow_booking,
            },
        };
        Some(
            Router::new()
                .route("/locations", get(list_locations::<TestDeps>))
                .route("/guards/{id}/location", get(guard_location::<TestDeps>))
                .route("/guards/{id}/history", get(guard_history::<TestDeps>))
                .with_state(deps),
        )
    }

    fn token(user_id: Uuid, role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        encode_jwt_with_key(user_id, role, 0, &ek, 15).unwrap().0
    }

    async fn get_status(app: Router, uri: &str, tok: Option<&str>) -> StatusCode {
        let mut b = Request::builder().method("GET").uri(uri);
        if let Some(t) = tok {
            b = b.header("authorization", format!("Bearer {t}"));
        }
        app.oneshot(b.body(Body::empty()).unwrap())
            .await
            .unwrap()
            .status()
    }

    // ----- /locations is admin-only (bulk = never customer/guard) -----

    #[tokio::test]
    async fn bulk_locations_requires_admin() {
        let Some(app) = router(false).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // customer → 403
        assert_eq!(
            get_status(app, "/locations", Some(&token(Uuid::new_v4(), "customer"))).await,
            StatusCode::FORBIDDEN
        );
        // guard → 403
        let Some(app) = router(false).await else {
            return;
        };
        assert_eq!(
            get_status(app, "/locations", Some(&token(Uuid::new_v4(), "guard"))).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn bulk_locations_rejects_missing_token() {
        let Some(app) = router(false).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(
            get_status(app, "/locations", None).await,
            StatusCode::UNAUTHORIZED
        );
    }

    // ----- per-guard IDOR gate -----

    #[tokio::test]
    async fn customer_without_active_booking_is_forbidden() {
        let Some(app) = router(false).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let guard = Uuid::new_v4();
        let uri = format!("/guards/{guard}/location");
        assert_eq!(
            get_status(app, &uri, Some(&token(Uuid::new_v4(), "customer"))).await,
            StatusCode::FORBIDDEN
        );
        // history is gated identically.
        let Some(app) = router(false).await else {
            return;
        };
        let uri = format!("/guards/{guard}/history");
        assert_eq!(
            get_status(app, &uri, Some(&token(Uuid::new_v4(), "customer"))).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn customer_with_active_booking_passes_idor_gate() {
        // allow=true → authz passes, then the lazy DB fails (≠ 403): the gate let it through.
        let Some(app) = router(true).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let guard = Uuid::new_v4();
        let uri = format!("/guards/{guard}/location");
        let status = get_status(app, &uri, Some(&token(Uuid::new_v4(), "customer"))).await;
        assert_ne!(
            status,
            StatusCode::FORBIDDEN,
            "a customer WITH an active booking must pass the IDOR gate"
        );
    }

    #[tokio::test]
    async fn guard_cannot_read_another_guard() {
        let Some(app) = router(false).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let other = Uuid::new_v4();
        let uri = format!("/guards/{other}/location");
        assert_eq!(
            get_status(app, &uri, Some(&token(Uuid::new_v4(), "guard"))).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn guard_reading_own_passes_idor_gate() {
        let Some(app) = router(false).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let me = Uuid::new_v4();
        let uri = format!("/guards/{me}/location");
        let status = get_status(app, &uri, Some(&token(me, "guard"))).await;
        assert_ne!(
            status,
            StatusCode::FORBIDDEN,
            "a guard reading its OWN location must pass the gate"
        );
    }

    // ----- /internal/online-guards: service-JWT guard (no Redis/DB needed for rejection) -----

    use crate::state::PresenceInternalDeps;
    use shared::service_jwt::HasServiceJwt;

    const SERVICE_SECRET: &str =
        "service-secret-at-least-64-characters-long-for-internal-hs256-test!!";

    #[derive(Clone)]
    struct InternalDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
    }
    impl HasServiceJwt for InternalDeps {
        fn service_decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
    }
    impl PresenceInternalDeps for InternalDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    /// Internal router over a lightweight state. The `ServiceCaller` extractor only needs the
    /// service decoding key — no Redis, no live DB. Rejected requests short-circuit at the guard
    /// before any DB access (mirrors profile's `internal_router` test).
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
                "/internal/online-guards",
                get(internal_online_guards::<InternalDeps>),
            )
            .with_state(deps)
    }

    async fn internal_status(tok: Option<&str>) -> StatusCode {
        let mut b = Request::builder()
            .method("GET")
            .uri("/internal/online-guards");
        if let Some(t) = tok {
            b = b.header("authorization", format!("Bearer {t}"));
        }
        internal_router()
            .oneshot(b.body(Body::empty()).unwrap())
            .await
            .unwrap()
            .status()
    }

    #[tokio::test]
    async fn online_guards_rejects_missing_token() {
        assert_eq!(internal_status(None).await, StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn online_guards_rejects_invalid_token() {
        assert_eq!(
            internal_status(Some("not.a.valid.jwt")).await,
            StatusCode::UNAUTHORIZED
        );
    }

    #[tokio::test]
    async fn online_guards_accepts_valid_service_token() {
        // A valid service-JWT (as minted by booking) must pass the guard; the handler then
        // queries the (unreachable) DB, so the response is NOT 401 — proving auth passed.
        use shared::service_jwt::encode_service_jwt;
        let ek = EncodingKey::from_secret(SERVICE_SECRET.as_bytes());
        let tok = encode_service_jwt("booking", &ek, 60).unwrap();
        assert_ne!(
            internal_status(Some(&tok)).await,
            StatusCode::UNAUTHORIZED,
            "valid service token must pass the guard"
        );
    }
}
