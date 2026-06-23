//! Outbound service-JWT'd read of presence's online-guard roster.
//!
//! The new-booking dispatch fan-out (`booking.requested` → push every ONLINE guard) needs the set
//! of guards currently LIVE. notification owns no presence registry, so — exactly like booking's
//! `discovery_client` — it MINTS a short-lived service-JWT (`encode_service_jwt("notification", …)`)
//! and GETs presence's `/internal/online-guards` (service-JWT'd, returns ids only, no PII). Never a
//! cross-schema query.
//!
//! Exposed behind the [`OnlineGuardsReader`] port so the consumer's fan-out is unit-testable with a
//! stub (no live presence). Cloneable (held in `AppState`); `reqwest::Client` is internally
//! ref-counted + connection-pooled.

use jsonwebtoken::EncodingKey;
use serde::Deserialize;
use uuid::Uuid;

use shared::error::AppError;
use shared::service_jwt::encode_service_jwt;

/// The live-guard ids from presence's `/internal/online-guards` (`{ success, data }` envelope).
#[derive(Debug, Default, Deserialize)]
struct OnlineGuards {
    #[serde(default)]
    guard_ids: Vec<Uuid>,
}

#[derive(Debug, Deserialize)]
struct Envelope<T> {
    data: Option<T>,
}

/// Port: read the ids of guards currently online. An `Err` is the SKIP-FAN-OUT signal — the
/// consumer logs it and notifies no one (rather than crashing / nack-storming) when presence is
/// unreachable. Implemented by [`HttpPresenceClient`] (real) and stubs in tests.
#[async_trait::async_trait]
pub trait OnlineGuardsReader: Send + Sync {
    async fn online_guard_ids(&self) -> Result<Vec<Uuid>, AppError>;
}

/// Mints a service-JWT and GETs presence's `/internal/online-guards`. Mirrors booking's
/// `HttpDiscoveryClient` (same minted-JWT + `{ success, data }` envelope pattern).
#[derive(Clone)]
pub struct HttpPresenceClient {
    http: reqwest::Client,
    /// Base URL of the presence service (no trailing slash).
    presence_url: String,
    /// Service-JWT signing key (shared `SERVICE_JWT_SECRET`).
    service_encoding_key: EncodingKey,
    /// Service-token TTL (seconds) — short-lived, per call.
    service_ttl_secs: i64,
}

impl HttpPresenceClient {
    pub fn new(
        http: reqwest::Client,
        presence_url: String,
        service_encoding_key: EncodingKey,
        service_ttl_secs: i64,
    ) -> Self {
        Self {
            http,
            presence_url: presence_url.trim_end_matches('/').to_string(),
            service_encoding_key,
            service_ttl_secs,
        }
    }

    fn mint(&self) -> Result<String, AppError> {
        encode_service_jwt(
            "notification",
            &self.service_encoding_key,
            self.service_ttl_secs,
        )
    }
}

#[async_trait::async_trait]
impl OnlineGuardsReader for HttpPresenceClient {
    async fn online_guard_ids(&self) -> Result<Vec<Uuid>, AppError> {
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
        // A 200 with no `data` is malformed, not "zero online" — surface as Err so the caller logs
        // + skips it distinctly (a present-but-empty `guard_ids` is a legitimate zero-online result).
        let online = envelope.data.ok_or_else(|| {
            tracing::warn!("presence online-guards 200 but missing data field");
            AppError::Internal("Online-guards lookup failed".to_string())
        })?;
        Ok(online.guard_ids)
    }
}
