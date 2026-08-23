//! pguard identity service — auth-core foundation (split from v1 auth).
//!
//! ISSUES + manages user JWTs that every other service validates: login, refresh
//! (RFC 6749 §6 rotation + reuse detection), logout, /me, and a service-JWT'd
//! force-revoke-all. Also the consumer of `pguard.events.user.compromised`.
//!
//! This file is wiring only — router, state, NATS consumer spawn, telemetry. Logic lives
//! in `domain/` (pure), `repo/` (DB), `events/` (consumer), `api/` (transport).

mod api;
mod domain;
mod events;
mod export_client;
mod models;
mod profile_status_client;
mod repo;
mod state;

use anyhow::Context;
use axum::routing::{delete, get, patch, post, put};
use axum::{Json, Router};

use shared::config::{DatabaseConfig, JwtConfig, RedisConfig, ServiceJwtConfig};
use shared::db::create_pool;
use shared::redis_client::create_connection_manager;

use crate::export_client::{ExportClient, ExportUpstream};
use crate::profile_status_client::ProfileStatusClient;
use crate::state::AppState;

const SERVICE_NAME: &str = "identity";
const PORT: u16 = 3001;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _telemetry = observability::init_telemetry(SERVICE_NAME);
    // Load the event-signing key (EVENT_SIGNING_SECRET, ≥64 chars) once at startup — fail-fast
    // so this service never publishes/consumes unsigned NATS events.
    shared_events::init_signing_key_from_env().map_err(|e| anyhow::anyhow!(e))?;

    // --- config (fail-fast at startup) ---
    let db_config = DatabaseConfig::from_env()?;
    let redis_config = RedisConfig::from_env()?;
    let jwt_config = JwtConfig::from_env()?;
    let service_jwt_config = ServiceJwtConfig::from_env()?;
    // AES-256 key sealing the per-user TOTP secret at rest (#144 2FA). Fail-fast at startup so a
    // misconfigured key can never reach the request path (which must never run with no/weak key).
    let totp_enc_key = {
        let hex = std::env::var("TOTP_ENC_KEY")
            .map_err(|_| anyhow::anyhow!("TOTP_ENC_KEY is required (64 hex chars / 32 bytes)"))?;
        domain::twofactor::parse_enc_key(&hex).map_err(|e| anyhow::anyhow!("{e:?}"))?
    };

    // --- infrastructure ---
    let db = create_pool(&db_config).await?;
    // Reconnecting manager (not a one-shot MultiplexedConnection) so a Redis restart self-heals
    // in the background instead of wedging the AuthUser revocation check forever (chaos case 3).
    let redis_conn = create_connection_manager(&redis_config.cache_url)
        .await
        .context("Redis cache connection (reconnecting)")?;

    // --- data-export aggregator (PDPA §19/§32): fan out to data owners' internal reads ---
    let export_http = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_millis(500))
        .timeout(std::time::Duration::from_secs(3))
        .build()
        .context("build export HTTP client")?;
    let export_client = ExportClient::new(
        export_http,
        service_jwt_config.encoding_key.clone(),
        service_jwt_config.ttl_secs,
        vec![
            ExportUpstream {
                section: "profile",
                base_url: svc_url("PROFILE_URL", "http://localhost:3002"),
            },
            ExportUpstream {
                section: "bookings",
                base_url: svc_url("BOOKING_URL", "http://localhost:3005"),
            },
            ExportUpstream {
                section: "payments",
                base_url: svc_url("PAYMENT_URL", "http://localhost:3006"),
            },
            ExportUpstream {
                section: "reviews",
                base_url: svc_url("RATING_URL", "http://localhost:3007"),
            },
        ],
    );

    // --- profile-status client: enriches /auth/me with `pending_roles` (best-effort) ---
    let profile_status_client = ProfileStatusClient::new(
        reqwest::Client::builder()
            .connect_timeout(std::time::Duration::from_millis(500))
            .timeout(std::time::Duration::from_secs(3))
            .build()
            .context("build profile-status HTTP client")?,
        service_jwt_config.encoding_key.clone(),
        service_jwt_config.ttl_secs,
        svc_url("PROFILE_URL", "http://localhost:3002"),
    );

    let state = AppState {
        db,
        redis_conn,
        jwt_config,
        service_jwt_config,
        export_client,
        profile_status_client,
        totp_enc_key,
    };

    // --- background JetStream consumers ---
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    // (1) user.compromised → force-revoke-all.
    {
        let consumer_state = state.clone();
        let nats = nats_url.clone();
        tokio::spawn(async move {
            if let Err(e) = events::run_consumer(consumer_state, &nats).await {
                tracing::error!("identity compromise consumer stopped: {e}");
            }
        });
    }
    // (2) user.approved → flip our own approval_status (closes the approval→login loop).
    {
        let consumer_state = state.clone();
        let nats = nats_url.clone();
        tokio::spawn(async move {
            events::approved::run_consumer(consumer_state, &nats).await;
        });
    }
    // (3) user.rejected → flip our own approval_status to `rejected` (distinct rejected state +
    //     re-apply). Separate durable from the approvals consumer.
    {
        let consumer_state = state.clone();
        let nats = nats_url.clone();
        tokio::spawn(async move {
            events::rejected::run_consumer(consumer_state, &nats).await;
        });
    }

    // --- HTTP router ---
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/auth/register", post(api::register::<AppState>))
        .route(
            "/auth/register/reissue",
            post(api::reissue_profile_token::<AppState>),
        )
        .route("/auth/register/add-role", post(api::add_role::<AppState>))
        // Post-OTP "does this phone already have an account?" probe (edge-public; carries a
        // phone_verified_token, verified but NOT consumed) → the app routes returning phones to PIN.
        .route("/auth/phone-status", post(api::phone_status::<AppState>))
        .route("/auth/login", post(api::login))
        .route("/auth/refresh", post(api::refresh))
        .route("/auth/logout", post(api::logout))
        .route(
            "/auth/me",
            get(api::me).put(api::update_me).delete(api::delete_me),
        )
        .route("/auth/password", put(api::change_password))
        // Change LOGIN phone: authenticated self (bearer/cookie+CSRF). Requires the current PIN
        // (step-up) + a single-use `phone_change` OTP token proving the NEW number; UNIQUE(phone)
        // guards against taking a number already in use (409 PHONE_TAKEN).
        .route("/auth/phone", patch(api::change_phone))
        // Forgot-PIN reset: edge-public (carries a single-use phone_verified_token in the body, not
        // an access token — like /auth/register). identity validates the token internally.
        .route("/auth/reset-pin", post(api::reset_pin))
        .route("/auth/revoke-all", post(api::revoke_all_sessions))
        // Multi-role (Option A): switch the active role (mint a token for an ENROLLED role) +
        // enroll a NEW role (mint a profile_token → pending second profile). Both are
        // authenticated self (bearer/cookie+CSRF), token-protected — NOT public.
        .route("/auth/switch-role", post(api::switch_role))
        .route("/auth/roles", post(api::enroll_role))
        // 2FA (#144): setup (provision) / enable / disable are self + bearer-gated; verify is the
        // edge-public second login step (carries a purpose challenge token, not an access token).
        .route("/auth/2fa/setup", post(api::setup_2fa))
        .route("/auth/2fa/enable", post(api::enable_2fa))
        .route("/auth/2fa/disable", post(api::disable_2fa))
        .route("/auth/2fa/verify", post(api::verify_2fa))
        // Per-device sessions (#144): list the caller's active families + revoke ONE device.
        .route("/auth/sessions", get(api::list_sessions))
        .route("/auth/sessions/{family_id}", delete(api::revoke_session))
        // Admin API tokens (#144): create-once / list / revoke (admin-gated in the handler).
        .route(
            "/admin/api-tokens",
            post(api::create_api_token).get(api::list_api_tokens),
        )
        .route("/admin/api-tokens/{id}", delete(api::revoke_api_token))
        .route("/me/data-export", get(api::data_export))
        // Admin user search (#138 per-user notify) — admin-gated in the handler. The gateway routes
        // `/admin/users/search` → identity (a more-specific rule than `/admin/users` → profile).
        .route("/admin/users/search", get(api::admin_search_users))
        .route(
            "/internal/users/{id}/revoke-all",
            post(api::internal_revoke_all::<AppState>),
        )
        // API-token verification for the gateway (service-JWT only; blocked at the edge). The
        // gateway calls this when it sees a `pguard_…` bearer to resolve the principal.
        .route(
            "/internal/api-tokens/verify",
            post(api::internal_verify_api_token::<AppState>),
        )
        // Internal batch id → {role, display_name} resolver (service-JWT only; blocked at the edge).
        // The profile resolver merges admin names from here (#142 Activity Log).
        .route(
            "/internal/users/names",
            post(api::internal_resolve_users::<AppState>),
        )
        .route("/metrics", get(observability::metrics_handler))
        .layer(shared::config::build_cors_layer())
        .layer(axum::middleware::from_fn(
            observability::telemetry_middleware,
        ))
        .with_state(state);

    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(service = SERVICE_NAME, %addr, "identity-service listening");
    axum::serve(listener, app).await?;
    Ok(())
}

/// A data-owner base URL from env, falling back to the dev default.
fn svc_url(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

async fn healthz() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": SERVICE_NAME,
        "version": env!("CARGO_PKG_VERSION"),
    }))
}
