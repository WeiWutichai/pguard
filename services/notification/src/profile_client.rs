//! Outbound service-JWT'd read of profile's broadcast-recipient roster.
//!
//! notification owns no user/role registry (only `fcm_tokens` + `notification_logs`), so a
//! broadcast to "all guards"/"all customers" MINTS a short-lived service-JWT
//! (`encode_service_jwt("notification", …)`) and GETs profile's
//! `/internal/profiles/recipients?audience=…` — never a cross-schema query. Mirrors booking's
//! `discovery_client` (same minted-JWT + `{ success, data }` envelope pattern). Cloneable
//! (held in `AppState`); `reqwest::Client` is internally ref-counted + connection-pooled.

use jsonwebtoken::EncodingKey;
use serde::Deserialize;
use uuid::Uuid;

use shared::error::AppError;
use shared::service_jwt::encode_service_jwt;

use crate::models::Audience;

#[derive(Debug, Deserialize)]
struct Envelope<T> {
    data: Option<T>,
}

#[derive(Debug, Default, Deserialize)]
struct Recipients {
    #[serde(default)]
    user_ids: Vec<Uuid>,
}

#[derive(Clone)]
pub struct ProfileClient {
    http: reqwest::Client,
    /// Base URL of the profile service (no trailing slash).
    profile_url: String,
    /// Service-JWT signing key (shared `SERVICE_JWT_SECRET`).
    service_encoding_key: EncodingKey,
    /// Service-token TTL (seconds) — short-lived, per call.
    service_ttl_secs: i64,
}

impl ProfileClient {
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

    fn mint(&self) -> Result<String, AppError> {
        encode_service_jwt(
            "notification",
            &self.service_encoding_key,
            self.service_ttl_secs,
        )
    }

    /// Resolve the recipient `user_id`s for `audience` (the broadcast fan-out target).
    pub async fn recipient_ids(&self, audience: Audience) -> Result<Vec<Uuid>, AppError> {
        let token = self.mint()?;
        let url = format!(
            "{}/internal/profiles/recipients?audience={}",
            self.profile_url,
            audience.as_db_str()
        );
        let resp = self
            .http
            .get(&url)
            .headers(observability::trace_headers())
            .header("Authorization", format!("Bearer {token}"))
            .send()
            .await
            .map_err(|e| {
                tracing::warn!("profile recipients transport error: {e}");
                AppError::Internal("Recipient lookup failed".to_string())
            })?;
        if !resp.status().is_success() {
            tracing::warn!("profile recipients returned {}", resp.status());
            return Err(AppError::Internal("Recipient lookup failed".to_string()));
        }
        let envelope: Envelope<Recipients> = resp.json().await.map_err(|e| {
            tracing::warn!("profile recipients decode error: {e}");
            AppError::Internal("Recipient lookup failed".to_string())
        })?;
        Ok(envelope.data.unwrap_or_default().user_ids)
    }
}
