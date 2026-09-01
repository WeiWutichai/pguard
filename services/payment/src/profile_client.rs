//! profile-client adapter — the cross-service read the GUARD-PAYOUT aggregator uses to build the
//! SCB file. THE MONEY PATH (payout side). payment mints a short-lived service-JWT
//! (`encode_service_jwt("payment", ...)`) and GETs profile's service-JWT'd internal reads:
//!   * `/internal/guards/{id}/payout-profile` → the guard's name + FULL tax id + address + phone
//!     (the ภ.ง.ด.53 recipient + PromptPay proxy). This is the ONLY surface returning the tax id in
//!     the clear; every owner/admin profile read masks it.
//!   * `/internal/org-settings` → the company (WHT payer) block. profile returns the "unset" default
//!     (all null) rather than 404 when unconfigured, so the caller surfaces a clear config error.
//!
//! A trait ([`ProfileReader`]) decouples the handler from `reqwest` so the payout aggregation tests
//! are hermetic. Mirrors [`crate::booking_client`].

use jsonwebtoken::EncodingKey;
use serde::Deserialize;
use uuid::Uuid;

use shared::error::AppError;
use shared::service_jwt::encode_service_jwt;

/// The guard PII for ONE payout recipient (profile `/internal/guards/{id}/payout-profile`). All
/// fields are `Option` — a guard missing a name/tax id is EXCLUDED from a WHT batch upstream (with a
/// warning), never silently paid with blanks.
#[derive(Debug, Clone, Deserialize)]
pub struct GuardPayoutProfile {
    pub full_name: Option<String>,
    /// FULL (unmasked) Thai national/tax id — the ภ.ง.ด.53 recipient TIN + PromptPay NAT proxy.
    pub tax_id: Option<String>,
    pub address: Option<String>,
    /// The guard's contact phone — the PromptPay MOB fallback proxy when no tax id is on file.
    pub phone: Option<String>,
}

/// The company (WHT payer) block (profile `/internal/org-settings`).
#[derive(Debug, Clone, Deserialize)]
pub struct OrgTaxInfo {
    pub company_name: Option<String>,
    pub tax_id: Option<String>,
    pub address: Option<String>,
}

/// Local mirror of the `{ success, data }` envelope (shared `ApiResponse` is `Serialize`-only).
#[derive(Debug, Deserialize)]
struct Envelope<T> {
    data: Option<T>,
}

/// Port: read the guard PII + company block the payout aggregator needs. Implemented by
/// [`HttpProfileReader`] (real) and a stub in tests.
#[allow(async_fn_in_trait)] // internal trait, never dyn.
pub trait ProfileReader: Send + Sync {
    /// The guard's payout PII, or `NotFound` when profile has no guard row for `guard_id`.
    async fn get_guard_payout_profile(
        &self,
        guard_id: Uuid,
    ) -> Result<GuardPayoutProfile, AppError>;
    /// The company WHT-payer block (never 404 — profile returns an all-null default when unset).
    async fn get_org_settings(&self) -> Result<OrgTaxInfo, AppError>;
}

/// Real reader: mints a service-JWT per call and GETs profile's internal reads.
#[derive(Clone)]
pub struct HttpProfileReader {
    http: reqwest::Client,
    /// Base URL of the profile service, e.g. `http://profile:3002` (no trailing slash).
    profile_url: String,
    service_encoding_key: EncodingKey,
    service_ttl_secs: i64,
}

impl HttpProfileReader {
    pub fn new(
        http: reqwest::Client,
        profile_url: String,
        service_encoding_key: EncodingKey,
        service_ttl_secs: i64,
    ) -> Self {
        Self {
            http,
            profile_url: profile_url.trim_end_matches('/').to_string(),
            service_encoding_key,
            service_ttl_secs,
        }
    }

    /// GET `url` with a freshly-minted service-JWT, decoding the `{ data }` envelope. `not_found_404`
    /// maps profile's 404 to `AppError::NotFound(context)`; when `None` a 404 is a generic Internal.
    async fn get_json<T: for<'de> Deserialize<'de>>(
        &self,
        url: &str,
        not_found_404: Option<&str>,
    ) -> Result<T, AppError> {
        let token =
            encode_service_jwt("payment", &self.service_encoding_key, self.service_ttl_secs)?;
        let resp = self
            .http
            .get(url)
            .headers(observability::trace_headers())
            .header("Authorization", format!("Bearer {token}"))
            .send()
            .await
            .map_err(|e| {
                tracing::warn!("profile internal read transport error: {e}");
                AppError::Internal("Profile lookup failed".to_string())
            })?;

        let status = resp.status();
        if status == reqwest::StatusCode::NOT_FOUND {
            if let Some(ctx) = not_found_404 {
                return Err(AppError::NotFound(ctx.to_string()));
            }
        }
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_else(|_| "unknown".to_string());
            tracing::warn!("profile internal read returned {status}: {body}");
            return Err(AppError::Internal("Profile lookup failed".to_string()));
        }

        let envelope: Envelope<T> = resp.json().await.map_err(|e| {
            tracing::warn!("profile internal read decode error: {e}");
            AppError::Internal("Profile lookup failed".to_string())
        })?;
        envelope
            .data
            .ok_or_else(|| AppError::Internal("Profile lookup returned no data".to_string()))
    }
}

impl ProfileReader for HttpProfileReader {
    async fn get_guard_payout_profile(
        &self,
        guard_id: Uuid,
    ) -> Result<GuardPayoutProfile, AppError> {
        let url = format!(
            "{}/internal/guards/{guard_id}/payout-profile",
            self.profile_url
        );
        self.get_json(&url, Some("Guard profile not found")).await
    }

    async fn get_org_settings(&self) -> Result<OrgTaxInfo, AppError> {
        let url = format!("{}/internal/org-settings", self.profile_url);
        self.get_json(&url, None).await
    }
}
