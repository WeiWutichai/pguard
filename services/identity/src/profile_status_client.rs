//! Small service-JWT client that asks profile which roles a user has a PENDING (submitted, not yet
//! approved) profile for. Feeds `/auth/me`'s `pending_roles` so the mobile mode-picker shows a
//! submitted second role as "pending approval" instead of re-offering its registration form.
//!
//! BEST-EFFORT: a mint failure / profile outage / non-2xx yields `[]` so it never breaks `/auth/me`
//! (the picker just falls back to "not enrolled" — the pre-existing behaviour). Mirrors the
//! service-JWT + trace-propagation pattern of [`crate::export_client::ExportClient`], single upstream.

use jsonwebtoken::EncodingKey;
use serde::Deserialize;
use uuid::Uuid;

use shared::service_jwt::encode_service_jwt;

/// Deserialize side of profile's `{ success, data: [..] }` envelope.
#[derive(Deserialize)]
struct Envelope {
    data: Option<Vec<String>>,
}

/// Cloneable (held in `AppState`); the `reqwest::Client` is internally ref-counted + pooled.
#[derive(Clone)]
pub struct ProfileStatusClient {
    http: reqwest::Client,
    service_encoding_key: EncodingKey,
    service_ttl_secs: i64,
    /// Profile base URL (no trailing slash), e.g. `http://profile:3002`.
    profile_base_url: String,
}

impl ProfileStatusClient {
    pub fn new(
        http: reqwest::Client,
        service_encoding_key: EncodingKey,
        service_ttl_secs: i64,
        profile_base_url: String,
    ) -> Self {
        Self {
            http,
            service_encoding_key,
            service_ttl_secs,
            profile_base_url,
        }
    }

    /// The roles `user_id` has a submitted-but-pending profile for. Best-effort → `[]` on any error.
    pub async fn pending_roles(&self, user_id: Uuid) -> Vec<String> {
        let token = match encode_service_jwt(
            "identity",
            &self.service_encoding_key,
            self.service_ttl_secs,
        ) {
            Ok(t) => t,
            Err(e) => {
                tracing::warn!("pending-roles: could not mint service token: {e}");
                return Vec::new();
            }
        };
        let url = format!(
            "{}/internal/users/{user_id}/pending-roles",
            self.profile_base_url
        );
        let result = self
            .http
            .get(&url)
            .headers(observability::trace_headers())
            .header("Authorization", format!("Bearer {token}"))
            .send()
            .await;
        match result {
            Ok(resp) if resp.status().is_success() => match resp.json::<Envelope>().await {
                Ok(env) => env.data.unwrap_or_default(),
                Err(e) => {
                    tracing::warn!("pending-roles decode error: {e}");
                    Vec::new()
                }
            },
            Ok(resp) => {
                tracing::warn!(status = %resp.status(), "pending-roles upstream non-success");
                Vec::new()
            }
            Err(e) => {
                tracing::warn!("pending-roles transport error: {e}");
                Vec::new()
            }
        }
    }
}
