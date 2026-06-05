//! Discovery clients — the service-JWT'd cross-service reads that `/available-guards`
//! aggregates: the APPROVED guard catalog (profile) + each guard's rating summary (rating).
//!
//! booking owns "discovery" (CLAUDE.md service map) but NOT the guard catalog (profile) or
//! reviews (rating). It MINTS a short-lived service-JWT (`encode_service_jwt("booking", ...)`)
//! and GETs each owner's `/internal/*` read — never a cross-schema query. Two ports decouple
//! the handler from `reqwest` so the aggregation is unit-testable with stubs (no live services).

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
        service_encoding_key: EncodingKey,
        service_ttl_secs: i64,
    ) -> Self {
        Self {
            http,
            profile_url: profile_url.trim_end_matches('/').to_string(),
            rating_url: rating_url.trim_end_matches('/').to_string(),
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
