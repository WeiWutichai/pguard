//! Discovery clients — the service-JWT'd cross-service reads that `/available-guards`
//! aggregates: the APPROVED guard catalog (profile), each guard's rating summary (rating), and
//! the set of guards currently LIVE (presence — the "พร้อมรับงาน" filter).
//!
//! booking owns "discovery" (CLAUDE.md service map) but NOT the guard catalog (profile), reviews
//! (rating), or live presence (presence). It MINTS a short-lived service-JWT
//! (`encode_service_jwt("booking", ...)`) and GETs each owner's `/internal/*` read — never a
//! cross-schema query. The ports decouple the handler from `reqwest` so the aggregation is
//! unit-testable with stubs (no live services).

use std::collections::HashSet;

use jsonwebtoken::EncodingKey;
use rust_decimal::Decimal;
use serde::Deserialize;
use uuid::Uuid;

use shared::error::AppError;
use shared::service_jwt::encode_service_jwt;

// ----- shared shapes (deserialized from the owners' `{ success, data }` envelopes) -----

/// One approved guard from profile's `/internal/guards`.
#[derive(Debug, Clone, Deserialize)]
pub struct CatalogGuard {
    pub user_id: Uuid,
    pub years_of_experience: Option<i32>,
}

/// A guard's rating summary from rating's `/internal/guards/{id}/rating-summary`. `Default`
/// (no reviews) is the best-effort fallback when the rating service is unreachable for a
/// guard, so one slow/down dependency never blanks the whole discovery list.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct GuardRatingSummary {
    pub average: Option<Decimal>,
    #[serde(default)]
    pub count: i64,
}

/// The live-guard ids from presence's `/internal/online-guards`.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct OnlineGuards {
    #[serde(default)]
    pub guard_ids: Vec<Uuid>,
}

#[derive(Debug, Deserialize)]
struct Envelope<T> {
    data: Option<T>,
}

// ----- Ports -----

/// Read the approved guard catalog (profile).
#[allow(async_fn_in_trait)] // internal trait, never dyn.
pub trait GuardCatalog: Send + Sync {
    async fn list_approved_guards(&self) -> Result<Vec<CatalogGuard>, AppError>;
}

/// Read one guard's rating summary (rating).
#[allow(async_fn_in_trait)]
pub trait RatingReader: Send + Sync {
    async fn guard_summary(&self, guard_id: Uuid) -> Result<GuardRatingSummary, AppError>;
}

/// Read the set of guards currently LIVE per presence (the "พร้อมรับงาน" filter). A `HashSet`
/// because the only use is membership filtering of the catalog. An `Err` here is the FAIL-OPEN
/// signal: the discovery handler logs a warning and shows the unfiltered list rather than
/// blocking every booking on a presence hiccup.
#[allow(async_fn_in_trait)]
pub trait PresenceReader: Send + Sync {
    async fn online_guard_ids(&self) -> Result<HashSet<Uuid>, AppError>;
}

/// Read the set of guards who currently hold an ACTIVE assignment (a booking in
/// accepted/en_route/arrived/pending_completion assigned to them) — the BUSY guards that
/// `/available-guards` must hide so a guard already working a job is never offered for another.
/// Unlike the other readers this is a LOCAL read of booking's OWN schema (booking owns its
/// bookings), not a cross-service call — but it is modelled as a port so the discovery handler
/// stays unit-testable with stubs. FAIL-CLOSED on error (unlike presence's fail-open): a DB
/// hiccup means we cannot prove a guard is free, so the handler hides nobody EXTRA but propagates
/// the error — see the handler for the exact policy.
#[allow(async_fn_in_trait)]
pub trait BusyGuardsReader: Send + Sync {
    async fn busy_guard_ids(&self) -> Result<HashSet<Uuid>, AppError>;
}

// ----- Real HTTP impls (one reqwest client + service-JWT minting, shared config) -----

/// Mints service-JWTs and GETs the `/internal/*` reads of profile + rating. Cloneable
/// (held in `AppState`); `reqwest::Client` is internally ref-counted + connection-pooled.
#[derive(Clone)]
pub struct HttpDiscoveryClient {
    http: reqwest::Client,
    /// Base URL of the profile service (no trailing slash).
    profile_url: String,
    /// Base URL of the rating service (no trailing slash).
    rating_url: String,
    /// Base URL of the presence service (no trailing slash).
    presence_url: String,
    /// Service-JWT signing key (shared `SERVICE_JWT_SECRET`).
    service_encoding_key: EncodingKey,
    /// Service-token TTL (seconds) — short-lived, per call.
    service_ttl_secs: i64,
}

impl HttpDiscoveryClient {
    pub fn new(
        http: reqwest::Client,
        profile_url: String,
        rating_url: String,
        presence_url: String,
        service_encoding_key: EncodingKey,
        service_ttl_secs: i64,
    ) -> Self {
        Self {
            http,
            profile_url: profile_url.trim_end_matches('/').to_string(),
            rating_url: rating_url.trim_end_matches('/').to_string(),
            presence_url: presence_url.trim_end_matches('/').to_string(),
            service_encoding_key,
            service_ttl_secs,
        }
    }

    fn mint(&self) -> Result<String, AppError> {
        encode_service_jwt("booking", &self.service_encoding_key, self.service_ttl_secs)
    }
}

impl GuardCatalog for HttpDiscoveryClient {
    async fn list_approved_guards(&self) -> Result<Vec<CatalogGuard>, AppError> {
        let token = self.mint()?;
        let url = format!("{}/internal/guards", self.profile_url);
        let resp = self
            .http
            .get(&url)
            .headers(observability::trace_headers())
            .header("Authorization", format!("Bearer {token}"))
            .send()
            .await
            .map_err(|e| {
                tracing::warn!("profile catalog transport error: {e}");
                AppError::Internal("Guard catalog lookup failed".to_string())
            })?;
        if !resp.status().is_success() {
            tracing::warn!("profile catalog returned {}", resp.status());
            return Err(AppError::Internal(
                "Guard catalog lookup failed".to_string(),
            ));
        }
        let envelope: Envelope<Vec<CatalogGuard>> = resp.json().await.map_err(|e| {
            tracing::warn!("profile catalog decode error: {e}");
            AppError::Internal("Guard catalog lookup failed".to_string())
        })?;
        Ok(envelope.data.unwrap_or_default())
    }
}

impl RatingReader for HttpDiscoveryClient {
    async fn guard_summary(&self, guard_id: Uuid) -> Result<GuardRatingSummary, AppError> {
        let token = self.mint()?;
        let url = format!(
            "{}/internal/guards/{guard_id}/rating-summary",
            self.rating_url
        );
        let resp = self
            .http
            .get(&url)
            .headers(observability::trace_headers())
            .header("Authorization", format!("Bearer {token}"))
            .send()
            .await
            .map_err(|e| {
                tracing::warn!("rating summary transport error: {e}");
                AppError::Internal("Rating summary lookup failed".to_string())
            })?;
        if !resp.status().is_success() {
            tracing::warn!("rating summary returned {}", resp.status());
            return Err(AppError::Internal(
                "Rating summary lookup failed".to_string(),
            ));
        }
        let envelope: Envelope<GuardRatingSummary> = resp.json().await.map_err(|e| {
            tracing::warn!("rating summary decode error: {e}");
            AppError::Internal("Rating summary lookup failed".to_string())
        })?;
        Ok(envelope.data.unwrap_or_default())
    }
}

/// The active-assignment exclusion reads booking's OWN schema, so the port is implemented
/// directly on the pool (a local trait on a foreign type — no orphan violation). `AppState`
/// hands its read-replica pool to the discovery handler as the `BusyGuardsReader`.
impl BusyGuardsReader for sqlx::PgPool {
    async fn busy_guard_ids(&self) -> Result<HashSet<Uuid>, AppError> {
        crate::repo::busy_guard_ids(self).await
    }
}

impl PresenceReader for HttpDiscoveryClient {
    async fn online_guard_ids(&self) -> Result<HashSet<Uuid>, AppError> {
        let token = self.mint()?;
        let url = format!("{}/internal/online-guards", self.presence_url);
        let resp = self
            .http
            .get(&url)
            .headers(observability::trace_headers())
            .header("Authorization", format!("Bearer {token}"))
            .send()
            .await
            .map_err(|e| {
                tracing::warn!("presence online-guards transport error: {e}");
                AppError::Internal("Online-guards lookup failed".to_string())
            })?;
        if !resp.status().is_success() {
            tracing::warn!("presence online-guards returned {}", resp.status());
            return Err(AppError::Internal(
                "Online-guards lookup failed".to_string(),
            ));
        }
        let envelope: Envelope<OnlineGuards> = resp.json().await.map_err(|e| {
            tracing::warn!("presence online-guards decode error: {e}");
            AppError::Internal("Online-guards lookup failed".to_string())
        })?;
        // A 200 with NO `data` field is malformed, not "zero guards online" — return Err so the
        // caller FAILS OPEN (shows the full approved list) instead of fail-closed (hides everyone).
        // A present `data` with an empty `guard_ids` is a legitimate zero-online result and is kept.
        let online = envelope.data.ok_or_else(|| {
            tracing::warn!("presence online-guards 200 but missing data field");
            AppError::Internal("Online-guards lookup failed".to_string())
        })?;
        Ok(online.guard_ids.into_iter().collect())
    }
}
