//! profile-client adapter — the cross-service reads the BANK-EXPORT aggregators use to build an SCB
//! file. THE MONEY PATH (payout + refund sides). payment mints a short-lived service-JWT
//! (`encode_service_jwt("payment", ...)`) and GETs profile's service-JWT'd internal reads:
//!   * `/internal/guards/{id}/payout-profile` → the guard's name + FULL tax id + address + phone
//!     (the ภ.ง.ด.53 recipient + PromptPay proxy). This is the ONLY surface returning the tax id in
//!     the clear; every owner/admin profile read masks it.
//!   * `/internal/customers/{user_id}/payout-profile` → the customer's name + phone + address — the
//!     stream-① REFUND destination, captured at REGISTRATION. Deliberately narrower: no tax id,
//!     because a refund withholds nothing.
//!   * `/internal/org-settings` → the company (WHT payer) block. profile returns the "unset" default
//!     (all null) rather than 404 when unconfigured, so the caller surfaces a clear config error.
//!     Read by the PAYOUT export only — a refund file carries no certificate to put a payer on.
//!
//! A trait ([`ProfileReader`]) decouples the handler from `reqwest` so the aggregation tests are
//! hermetic. Mirrors [`crate::booking_client`].

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

/// The customer PII for ONE refund recipient (profile
/// `/internal/customers/{user_id}/payout-profile`) — stream ① *ยอดที่ต้องโอนคืนกับคนจ้าง*.
///
/// Deliberately NARROWER than [`GuardPayoutProfile`]: there is no `tax_id`, because a refund is the
/// customer's own money coming back rather than assessable income — nothing is withheld, so no
/// ภ.ง.ด. certificate is issued and no TIN is needed (or exposed) to send one.
///
/// Every field is `Option`, and each missing one means something different to the aggregator: no
/// `phone` is UNREFUNDABLE (there is no PromptPay destination at all), no `full_name` fails SCB's
/// mandatory recipient-name column, and `address` is genuinely optional on a credit line. All three
/// come back RAW, exactly as stored — payment owns normalisation (`digits_only` at the writer
/// boundary), the same contract as the guard read; two internal endpoints disagreeing about who
/// normalises is how a proxy silently changes length, and therefore proxy TYPE, between streams.
#[derive(Debug, Clone, Deserialize)]
pub struct CustomerPayoutProfile {
    pub full_name: Option<String>,
    /// The PromptPay **MOB** proxy — `customer_profiles.contact_phone` when the customer set one,
    /// else the account's LOGIN phone, which profile resolves from identity on our behalf. That hop
    /// is why payment needs no `IDENTITY_URL` of its own.
    pub phone: Option<String>,
    pub address: Option<String>,
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
    /// The customer's REFUND destination, or `NotFound` when profile has no customer row for
    /// `customer_id`. A `NotFound` excludes that ONE customer from the batch (with a Thai reason);
    /// any other error fails the run loudly — silently skipping a customer on a network blip would
    /// leave them unrefunded with nobody told.
    async fn get_customer_payout_profile(
        &self,
        customer_id: Uuid,
    ) -> Result<CustomerPayoutProfile, AppError>;
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

    async fn get_customer_payout_profile(
        &self,
        customer_id: Uuid,
    ) -> Result<CustomerPayoutProfile, AppError> {
        let url = format!(
            "{}/internal/customers/{customer_id}/payout-profile",
            self.profile_url
        );
        self.get_json(&url, Some("Customer profile not found"))
            .await
    }

    async fn get_org_settings(&self) -> Result<OrgTaxInfo, AppError> {
        let url = format!("{}/internal/org-settings", self.profile_url);
        self.get_json(&url, None).await
    }
}
