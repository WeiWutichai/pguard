//! Environment-driven configuration + CORS. Ported from v1.
//!
//! v2 addition: [`ServiceJwtConfig`] holds the *separate* service-to-service JWT
//! secret (`SERVICE_JWT_SECRET`), distinct from the user `JWT_SECRET`. See
//! CLAUDE.md "Service auth (internal)".

use axum::http::header::{HeaderName, ACCEPT, AUTHORIZATION, CONTENT_TYPE, COOKIE, ORIGIN};
use axum::http::{HeaderValue, Method};
use tower_http::cors::CorsLayer;

use crate::error::AppError;

/// The allowed browser origins from `CORS_ALLOWED_ORIGINS` (comma-separated, trimmed),
/// defaulting to `http://localhost:3000` for dev. Single source of truth so the CORS layer
/// and any manual origin check (e.g. the gateway's WebSocket-upgrade gate, which CORS does
/// NOT cover) agree on exactly the same allowlist.
pub fn cors_allowed_origins() -> Vec<String> {
    std::env::var("CORS_ALLOWED_ORIGINS")
        .unwrap_or_else(|_| "http://localhost:3000".to_string())
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

/// Build a CORS layer from `CORS_ALLOWED_ORIGINS` (comma-separated).
/// Defaults to `http://localhost:3000` for dev. Never permissive — `allow_credentials(true)`
/// forbids the `*` wildcard, so origins are always explicit.
pub fn build_cors_layer() -> CorsLayer {
    let origins: Vec<HeaderValue> = cors_allowed_origins()
        .iter()
        .filter_map(|s| s.parse().ok())
        .collect();

    CorsLayer::new()
        .allow_origin(origins)
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PUT,
            Method::DELETE,
            Method::PATCH,
            Method::OPTIONS,
        ])
        .allow_headers([
            AUTHORIZATION,
            ACCEPT,
            CONTENT_TYPE,
            ORIGIN,
            COOKIE,
            HeaderName::from_static("x-requested-with"),
        ])
        .allow_credentials(true)
}

#[derive(Debug, Clone)]
pub struct DatabaseConfig {
    /// Primary (writes + read-after-write). In prod this points at pgbouncer (transaction
    /// pooling), which fronts Postgres — so `max_connections` is the app's pooled client
    /// count, not raw server connections (fixes the v1 6×20 single-DB explosion).
    pub url: String,
    /// Read replica for list/report/discovery reads (C5.3). `None` → reads fall back to the
    /// primary so single-node dev/test works unchanged.
    pub read_url: Option<String>,
    pub max_connections: u32,
    /// Pool size for the read replica (smaller — it only serves read-heavy list/report reads).
    pub read_max_connections: u32,
}

#[derive(Debug, Clone)]
pub struct RedisConfig {
    pub cache_url: String,
    pub pubsub_url: Option<String>,
}

#[derive(Clone)]
pub struct JwtConfig {
    pub secret: String,
    /// Access-token lifetime in minutes (default 15, OWASP for high-sensitivity).
    pub expiry_minutes: i64,
    pub encoding_key: jsonwebtoken::EncodingKey,
    pub decoding_key: jsonwebtoken::DecodingKey,
}

impl std::fmt::Debug for JwtConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("JwtConfig")
            .field("expiry_minutes", &self.expiry_minutes)
            .field("secret", &"[REDACTED]")
            .finish()
    }
}

/// Separate secret for service-to-service JWTs (v2). See [`crate::service_jwt`].
#[derive(Clone)]
pub struct ServiceJwtConfig {
    pub encoding_key: jsonwebtoken::EncodingKey,
    pub decoding_key: jsonwebtoken::DecodingKey,
    /// Service-token lifetime in seconds (default 60 — short-lived, per call).
    pub ttl_secs: i64,
}

impl std::fmt::Debug for ServiceJwtConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ServiceJwtConfig")
            .field("ttl_secs", &self.ttl_secs)
            .finish()
    }
}

#[derive(Debug, Clone)]
pub struct S3Config {
    pub endpoint: String,
    pub access_key: String,
    pub secret_key: String,
    pub bucket: String,
}

fn require_env(key: &str) -> Result<String, AppError> {
    std::env::var(key).map_err(|_| AppError::Internal(format!("Missing env var: {key}")))
}

fn optional_env(key: &str) -> Option<String> {
    std::env::var(key).ok()
}

/// Value-aware boolean parse for env flags. Returns `true` ONLY for an explicit
/// truthy value (`true`/`1`/`yes`/`on`/`y`, case-insensitive, surrounding whitespace
/// ignored). Everything else — `false`, `0`, the empty string, an unrecognized value,
/// or unset (`None`) — is `false`.
///
/// This exists because `std::env::var(K).is_ok()` is *presence-based*: it treats any
/// value (even `"false"`) as set/true. That footgun once gated otp's real SMS sender
/// (`SMS_DISABLED=false` silently disabled SMS). Env flags must be parsed by value.
pub fn parse_env_bool(val: Option<&str>) -> bool {
    matches!(
        val.map(|s| s.trim().to_ascii_lowercase()).as_deref(),
        Some("true" | "1" | "yes" | "on" | "y")
    )
}

impl DatabaseConfig {
    pub fn from_env() -> Result<Self, AppError> {
        Ok(Self {
            url: require_env("DATABASE_URL")?,
            // Optional: empty/unset → reads fall back to the primary (single-node dev).
            read_url: optional_env("DATABASE_READ_URL").filter(|s| !s.trim().is_empty()),
            max_connections: optional_env("DATABASE_MAX_CONNECTIONS")
                .and_then(|v| v.parse().ok())
                .unwrap_or(20),
            read_max_connections: optional_env("DATABASE_READ_MAX_CONNECTIONS")
                .and_then(|v| v.parse().ok())
                .unwrap_or(10),
        })
    }

    /// The URL the read pool should connect to, with a tag for logging. Pure (no I/O) so the
    /// replica-vs-fallback decision is unit-testable. `read_url` when set, else the primary.
    pub fn read_target(&self) -> (&str, &'static str) {
        match &self.read_url {
            Some(u) => (u.as_str(), "replica"),
            None => (self.url.as_str(), "primary-fallback"),
        }
    }
}

impl RedisConfig {
    pub fn from_env() -> Result<Self, AppError> {
        Ok(Self {
            cache_url: require_env("REDIS_CACHE_URL")?,
            pubsub_url: optional_env("REDIS_PUBSUB_URL"),
        })
    }
}

impl JwtConfig {
    pub fn from_env() -> Result<Self, AppError> {
        let secret = require_env("JWT_SECRET")?;
        if secret.len() < 64 {
            return Err(AppError::Internal(
                "JWT_SECRET must be at least 64 characters".to_string(),
            ));
        }
        let encoding_key = jsonwebtoken::EncodingKey::from_secret(secret.as_bytes());
        let decoding_key = jsonwebtoken::DecodingKey::from_secret(secret.as_bytes());
        Ok(Self {
            secret,
            expiry_minutes: optional_env("JWT_EXPIRY_MINUTES")
                .and_then(|v| v.parse().ok())
                .unwrap_or(15),
            encoding_key,
            decoding_key,
        })
    }
}

impl ServiceJwtConfig {
    pub fn from_env() -> Result<Self, AppError> {
        let secret = require_env("SERVICE_JWT_SECRET")?;
        if secret.len() < 64 {
            return Err(AppError::Internal(
                "SERVICE_JWT_SECRET must be at least 64 characters".to_string(),
            ));
        }
        Ok(Self {
            encoding_key: jsonwebtoken::EncodingKey::from_secret(secret.as_bytes()),
            decoding_key: jsonwebtoken::DecodingKey::from_secret(secret.as_bytes()),
            ttl_secs: optional_env("SERVICE_JWT_TTL_SECS")
                .and_then(|v| v.parse().ok())
                .unwrap_or(60),
        })
    }
}

impl S3Config {
    pub fn from_env() -> Result<Self, AppError> {
        Ok(Self {
            endpoint: require_env("S3_ENDPOINT")?,
            access_key: require_env("S3_ACCESS_KEY")?,
            secret_key: require_env("S3_SECRET_KEY")?,
            bucket: require_env("S3_BUCKET")?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // Env-var tests mutate process state; serialize them.
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn with_env_vars<F: FnOnce()>(vars: &[(&str, &str)], f: F) {
        let _lock = ENV_LOCK.lock().unwrap();
        let previous: Vec<_> = vars
            .iter()
            .map(|(k, _)| (*k, std::env::var(k).ok()))
            .collect();
        for (k, v) in vars {
            std::env::set_var(k, v);
        }
        f();
        for (k, prev) in &previous {
            match prev {
                Some(v) => std::env::set_var(k, v),
                None => std::env::remove_var(k),
            }
        }
    }

    #[test]
    fn database_config_reads_from_env() {
        with_env_vars(&[("DATABASE_URL", "postgres://localhost/pguard")], || {
            let cfg = DatabaseConfig::from_env().unwrap();
            assert_eq!(cfg.url, "postgres://localhost/pguard");
            assert_eq!(cfg.max_connections, 20);
        });
    }

    #[test]
    fn jwt_config_reads_from_env() {
        with_env_vars(
            &[(
                "JWT_SECRET",
                "super-secret-key-that-is-at-least-64-characters-long-for-hs256-security!",
            )],
            || {
                let cfg = JwtConfig::from_env().unwrap();
                assert_eq!(cfg.expiry_minutes, 15);
            },
        );
    }

    #[test]
    fn jwt_config_fails_with_short_secret() {
        with_env_vars(&[("JWT_SECRET", "too-short")], || {
            assert!(JwtConfig::from_env().is_err());
        });
    }

    #[test]
    fn service_jwt_config_reads_from_env() {
        with_env_vars(
            &[(
                "SERVICE_JWT_SECRET",
                "service-secret-that-is-at-least-64-characters-long-for-hs256-internal!!",
            )],
            || {
                let cfg = ServiceJwtConfig::from_env().unwrap();
                assert_eq!(cfg.ttl_secs, 60);
            },
        );
    }

    #[test]
    fn service_jwt_config_fails_with_short_secret() {
        with_env_vars(&[("SERVICE_JWT_SECRET", "too-short")], || {
            assert!(ServiceJwtConfig::from_env().is_err());
        });
    }

    #[test]
    fn redis_config_reads_from_env() {
        with_env_vars(
            &[("REDIS_CACHE_URL", "redis://:pass@localhost:6379")],
            || {
                let cfg = RedisConfig::from_env().unwrap();
                assert_eq!(cfg.cache_url, "redis://:pass@localhost:6379");
                assert!(cfg.pubsub_url.is_none());
            },
        );
    }

    // ----- parse_env_bool: value-aware, not presence-based (the SMS_DISABLED footgun) -----

    #[test]
    fn parse_env_bool_truthy_values_are_true() {
        for v in ["true", "True", "TRUE", "TrUe", "1", "yes", "YES", "on", "y", " true "] {
            assert!(parse_env_bool(Some(v)), "{v:?} should parse as true");
        }
    }

    #[test]
    fn parse_env_bool_falsy_values_are_false() {
        // The crux: "false"/"0"/empty must NOT disable (the old `.is_ok()` got this wrong).
        for v in ["false", "False", "0", "no", "off", "n", "", "  ", "disabled", "banana"] {
            assert!(!parse_env_bool(Some(v)), "{v:?} should parse as false");
        }
    }

    #[test]
    fn parse_env_bool_unset_is_false() {
        assert!(!parse_env_bool(None));
    }
}
