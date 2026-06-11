//! FCM adapter — OAuth2 service-account auth + HTTP v1 push.
//!
//! Ported from v1 (`../guard-dispatch/services/notification/src/fcm.rs` + `service.rs`),
//! re-implemented behind a [`Pusher`] port so domain/consumer/handler code stays
//! transport-agnostic and unit-testable. `domain` never imports this module.

use std::sync::Arc;

use async_trait::async_trait;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;

use shared::error::AppError;

const FCM_SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_REFRESH_BUFFER_SECS: i64 = 300; // refresh 5 min before expiry

/// A push to deliver to one user's registered devices.
#[derive(Debug, Clone)]
pub struct PushMessage {
    pub tokens: Vec<String>,
    pub title: String,
    pub body: String,
    /// Arbitrary JSON; flattened to string:string for FCM `data`.
    pub data: serde_json::Value,
}

/// Port: deliver a push. Implemented by [`FcmPusher`] (real) and [`NoopPusher`] (dev/tests).
#[async_trait]
pub trait Pusher: Send + Sync {
    async fn push(&self, msg: &PushMessage) -> Result<(), AppError>;
}

/// notification's FCM-gating policy: real push is disabled ONLY when `FCM_DISABLED` carries a
/// truthy value (`true`/`1`/`yes`/`on`, case-insensitive). `false`/`0`/empty/unset keep real
/// push ENABLED. Pass `std::env::var("FCM_DISABLED").ok().as_deref()`.
///
/// Fixes the footgun where presence-based `std::env::var("FCM_DISABLED").is_ok()` treated *any*
/// value — including `"false"` — as "disable", so `FCM_DISABLED=false` silently dropped all push
/// (compose.prod's `${FCM_DISABLED:-false}` default = prod push off forever, unnoticed). Mirrors
/// otp's `sms_disabled`. When push is ENABLED, `FcmConfig::from_env` fail-fasts without creds —
/// so a misconfig is loud at boot, never a silent no-op.
pub fn fcm_disabled(raw: Option<&str>) -> bool {
    shared::config::parse_env_bool(raw)
}

/// Dev/test pusher — logs and succeeds. Selected when `FCM_DISABLED` is truthy.
pub struct NoopPusher;

#[async_trait]
impl Pusher for NoopPusher {
    async fn push(&self, msg: &PushMessage) -> Result<(), AppError> {
        tracing::info!(devices = msg.tokens.len(), title = %msg.title, "noop push (FCM disabled)");
        Ok(())
    }
}

/// Parsed service-account JSON fields needed for OAuth2.
#[derive(Debug, Clone)]
pub struct ServiceAccount {
    pub project_id: String,
    pub client_email: String,
    pub private_key: String,
    pub token_uri: String,
}

impl ServiceAccount {
    pub fn from_file(path: &str) -> Result<Self, AppError> {
        let content = std::fs::read_to_string(path).map_err(|e| {
            AppError::Internal(format!("Failed to read service account file '{path}': {e}"))
        })?;

        #[derive(Deserialize)]
        struct Raw {
            project_id: String,
            client_email: String,
            private_key: String,
            token_uri: String,
        }

        let raw: Raw = serde_json::from_str(&content).map_err(|e| {
            AppError::Internal(format!("Failed to parse service account JSON: {e}"))
        })?;

        Ok(Self {
            project_id: raw.project_id,
            client_email: raw.client_email,
            private_key: raw.private_key,
            token_uri: raw.token_uri,
        })
    }
}

/// FCM config — **fail-fast**: requires `FCM_SERVICE_ACCOUNT_PATH`. Never defaults to a
/// placeholder (v2 spec item 5). For local dev without FCM, set `FCM_DISABLED=1` instead.
pub struct FcmConfig {
    pub service_account: ServiceAccount,
}

impl FcmConfig {
    pub fn from_env() -> Result<Self, AppError> {
        let path = std::env::var("FCM_SERVICE_ACCOUNT_PATH").map_err(|_| {
            AppError::Internal(
                "Missing env var: FCM_SERVICE_ACCOUNT_PATH (set FCM_DISABLED=1 for dev without FCM)"
                    .to_string(),
            )
        })?;
        Ok(Self {
            service_account: ServiceAccount::from_file(&path)?,
        })
    }
}

#[derive(Debug, Clone)]
struct CachedToken {
    access_token: String,
    expires_at: i64,
}

/// Real FCM pusher: caches a short-lived OAuth2 access token (auto-refreshes ~5 min
/// before expiry) and posts to the FCM HTTP v1 API per device token.
#[derive(Clone)]
pub struct FcmPusher {
    service_account: ServiceAccount,
    http: reqwest::Client,
    cached: Arc<RwLock<Option<CachedToken>>>,
}

impl FcmPusher {
    pub fn new(config: FcmConfig, http: reqwest::Client) -> Self {
        Self {
            service_account: config.service_account,
            http,
            cached: Arc::new(RwLock::new(None)),
        }
    }

    async fn access_token(&self) -> Result<String, AppError> {
        {
            let cached = self.cached.read().await;
            if let Some(t) = cached.as_ref() {
                if t.expires_at - Utc::now().timestamp() > TOKEN_REFRESH_BUFFER_SECS {
                    return Ok(t.access_token.clone());
                }
            }
        }

        let mut cached = self.cached.write().await;
        if let Some(t) = cached.as_ref() {
            if t.expires_at - Utc::now().timestamp() > TOKEN_REFRESH_BUFFER_SECS {
                return Ok(t.access_token.clone());
            }
        }

        let fresh = self.exchange_jwt_for_token().await?;
        let access = fresh.access_token.clone();
        *cached = Some(fresh);
        Ok(access)
    }

    async fn exchange_jwt_for_token(&self) -> Result<CachedToken, AppError> {
        let now = Utc::now().timestamp();

        #[derive(Serialize)]
        struct GoogleClaims {
            iss: String,
            scope: String,
            aud: String,
            iat: i64,
            exp: i64,
        }

        let claims = GoogleClaims {
            iss: self.service_account.client_email.clone(),
            scope: FCM_SCOPE.to_string(),
            aud: self.service_account.token_uri.clone(),
            iat: now,
            exp: now + 3600,
        };

        let key =
            jsonwebtoken::EncodingKey::from_rsa_pem(self.service_account.private_key.as_bytes())
                .map_err(|e| AppError::Internal(format!("Failed to parse RSA private key: {e}")))?;
        let header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256);
        let jwt = jsonwebtoken::encode(&header, &claims, &key)
            .map_err(|e| AppError::Internal(format!("Failed to sign Google JWT: {e}")))?;

        #[derive(Deserialize)]
        struct TokenResponse {
            access_token: String,
            expires_in: i64,
        }

        let response = self
            .http
            .post(&self.service_account.token_uri)
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", &jwt),
            ])
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("Google token exchange failed: {e}")))?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response
                .text()
                .await
                .unwrap_or_else(|_| "unknown".to_string());
            return Err(AppError::Internal(format!(
                "Google token exchange returned {status}: {body}"
            )));
        }

        let token: TokenResponse = response
            .json()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to parse token response: {e}")))?;

        Ok(CachedToken {
            access_token: token.access_token,
            expires_at: now + token.expires_in,
        })
    }

    async fn send_one(&self, access_token: &str, device_token: &str, msg: &PushMessage) {
        let url = format!(
            "https://fcm.googleapis.com/v1/projects/{}/messages:send",
            self.service_account.project_id
        );

        // FCM `data` must be flat string:string. Stringify any non-string values.
        let mut data_map = serde_json::Map::new();
        if let serde_json::Value::Object(obj) = &msg.data {
            for (k, v) in obj {
                let s = match v {
                    serde_json::Value::String(s) => s.clone(),
                    other => other.to_string(),
                };
                data_map.insert(k.clone(), serde_json::Value::String(s));
            }
        }

        let message = serde_json::json!({
            "message": {
                "token": device_token,
                "notification": { "title": msg.title, "body": msg.body },
                "data": serde_json::Value::Object(data_map),
                "android": {
                    "priority": "high",
                    "notification": { "sound": "default", "channel_id": "default" }
                },
                "apns": {
                    "headers": { "apns-priority": "10" },
                    "payload": { "aps": { "sound": "default", "content-available": 1 } }
                }
            }
        });

        let result = self
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {access_token}"))
            .json(&message)
            .send()
            .await;

        match result {
            Ok(resp) if resp.status().is_success() => {}
            Ok(resp) => {
                let status = resp.status();
                let body = resp.text().await.unwrap_or_else(|_| "unknown".to_string());
                tracing::warn!("FCM API error: status={status}, body={body}");
            }
            Err(e) => tracing::warn!("FCM request failed: {e}"),
        }
    }
}

#[async_trait]
impl Pusher for FcmPusher {
    async fn push(&self, msg: &PushMessage) -> Result<(), AppError> {
        if msg.tokens.is_empty() {
            return Ok(());
        }
        // A failed access-token fetch is fatal for the batch; per-device send errors
        // are logged and skipped (best-effort fan-out).
        let access = self.access_token().await?;
        for token in &msg.tokens {
            self.send_one(&access, token, msg).await;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::fcm_disabled;

    #[test]
    fn fcm_disabled_is_value_aware_not_presence_based() {
        // Truthy → disabled.
        for v in ["true", "TRUE", "1", "yes", "on", "  true  "] {
            assert!(fcm_disabled(Some(v)), "{v:?} should disable FCM");
        }
        // Falsy / empty / unset → push ENABLED (the old presence-based gate wrongly disabled these).
        for v in ["false", "FALSE", "0", "no", "off", ""] {
            assert!(!fcm_disabled(Some(v)), "{v:?} must NOT disable FCM");
        }
        assert!(!fcm_disabled(None), "unset must NOT disable FCM");
    }
}
