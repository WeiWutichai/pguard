//! Service-to-service client for identity's internal name resolver (`POST /internal/users/names`).
//!
//! profile owns the guard/customer display names, but ADMINS have no profile row — their name lives
//! ONLY in identity (`identity.users.display_name`). So the admin name-resolver
//! (`POST /admin/users/resolve`) resolves guard/customer locally, then asks identity for the names
//! of the STILL-UNRESOLVED ids and merges the admin entries in. This client mints a short-lived
//! service-JWT and POSTs the unresolved ids; it is **best-effort** — an identity outage degrades to
//! "admin ids omitted" (the web hook already renders a fallback) rather than failing the whole
//! resolve, mirroring identity's own best-effort export fan-out.
//!
//! The same client also feeds the admin approval queues (`GET /admin/customer-profiles` /
//! `/admin/guard-profiles`) the applicant's LOGIN phone — the number on `identity.users`, which
//! profile does not (and must not) store. Same best-effort contract: an unreachable identity means
//! `login_phone: null` on those rows, never a failed list.

use std::collections::HashMap;

use jsonwebtoken::EncodingKey;
use serde::Deserialize;
use uuid::Uuid;

use shared::service_jwt::encode_service_jwt;

/// One resolved identity from identity's `/internal/users/names` — `{ role, display_name, phone }`.
///
/// `phone` is the account's LOGIN number (`identity.users.phone`, `NOT NULL` there) — the identity
/// every pguard account is keyed on. It is `Option` on THIS side purely for resilience, not because
/// identity may omit it: during a rolling deploy an older identity build answers without the field,
/// and the whole envelope must still decode (a hard-required field would turn one stale pod into a
/// blank admin list). A `None` therefore means "identity didn't tell us", never "this user has no
/// phone".
#[derive(Debug, Clone, Deserialize)]
pub struct IdentityName {
    pub role: String,
    pub display_name: Option<String>,
    #[serde(default)]
    pub phone: Option<String>,
}

/// `{ success, data }` envelope: `data` is the id → name map (unknown ids omitted upstream).
#[derive(Deserialize)]
struct Envelope {
    data: Option<HashMap<Uuid, IdentityName>>,
}

/// Resolves user ids to `{ role, display_name, phone }` against identity over a service-JWT.
/// Decoupled behind [`IdentityResolver`] so the profile handler is unit-testable with a stub (no
/// live identity / network), mirroring profile's `BookingAuthz` seam.
#[allow(async_fn_in_trait)] // internal trait, never `dyn`.
pub trait IdentityResolver: Send + Sync {
    /// Resolve `ids` to a map id → `{ role, display_name, phone }` in ONE round-trip — callers pass
    /// a whole page of ids, never one id at a time. Best-effort: on ANY failure (token mint,
    /// transport, non-2xx, decode) returns an EMPTY map so the caller's local resolution still
    /// stands. An empty `ids` short-circuits without a network call.
    async fn resolve(&self, ids: &[Uuid]) -> HashMap<Uuid, IdentityName>;
}

/// HTTP-backed [`IdentityResolver`] — mints a service-JWT + POSTs to identity. Cloneable (held in
/// `AppState`); `reqwest::Client` is internally ref-counted + connection-pooled.
#[derive(Clone)]
pub struct HttpIdentityResolver {
    http: reqwest::Client,
    base_url: String,
    service_encoding_key: EncodingKey,
    service_ttl_secs: i64,
}

impl HttpIdentityResolver {
    pub fn new(
        http: reqwest::Client,
        base_url: String,
        service_encoding_key: EncodingKey,
        service_ttl_secs: i64,
    ) -> Self {
        Self {
            http,
            base_url,
            service_encoding_key,
            service_ttl_secs,
        }
    }
}

impl IdentityResolver for HttpIdentityResolver {
    async fn resolve(&self, ids: &[Uuid]) -> HashMap<Uuid, IdentityName> {
        if ids.is_empty() {
            return HashMap::new();
        }
        let token = match encode_service_jwt(
            "profile",
            &self.service_encoding_key,
            self.service_ttl_secs,
        ) {
            Ok(t) => t,
            Err(e) => {
                tracing::warn!("identity resolver: could not mint service token: {e}");
                return HashMap::new();
            }
        };
        let url = format!("{}/internal/users/names", self.base_url);
        let trace = observability::trace_headers();
        let result = self
            .http
            .post(&url)
            .headers(trace)
            .header("Authorization", format!("Bearer {token}"))
            .json(&serde_json::json!({ "ids": ids }))
            .send()
            .await;
        match result {
            Ok(resp) if resp.status().is_success() => match resp.json::<Envelope>().await {
                Ok(env) => env.data.unwrap_or_default(),
                Err(e) => {
                    tracing::warn!("identity resolver: identity decode error: {e}");
                    HashMap::new()
                }
            },
            Ok(resp) => {
                tracing::warn!(status = %resp.status(), "identity resolver: identity non-success");
                HashMap::new()
            }
            Err(e) => {
                tracing::warn!("identity resolver: identity transport error: {e}");
                HashMap::new()
            }
        }
    }
}
