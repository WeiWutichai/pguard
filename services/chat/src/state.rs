//! Shared application state + the trait seams the extractors/handlers require.
//!
//! Like calling/profile, handlers are generic over capability traits ([`ChatDeps`] for the
//! client surface, [`ChatInternalDeps`] for the service-JWT'd internal surface) so the
//! `AuthUser`/`ServiceCaller` guards + the IDOR/read-only logic are unit-testable with a
//! lightweight state (lazy DB pool, no live S3/NATS).
//!
//! Redis appears twice: `redis_conn` is the multiplexed connection the `AuthUser` extractor uses
//! for the jti revocation blocklist; `pubsub_conn`/`pubsub_client` are the chat fan-out — a
//! publisher connection + the client a WS session opens a dedicated subscriber on. Per the spec
//! this is Redis pub/sub (topic `chat:{conversation_id}`) so delivery works ACROSS chat replicas
//! (unlike calling's in-process registry).

use jsonwebtoken::DecodingKey;
use sqlx::PgPool;

use shared::auth::HasJwtSecret;
use shared::config::JwtConfig;
use shared::service_jwt::HasServiceJwt;

use crate::s3::S3Client;

#[derive(Clone)]
pub struct AppState {
    /// Primary pool — writes + read-after-write (pgbouncer-fronted in prod).
    pub db: PgPool,
    /// Read replica — the enriched conversation list (a read-heavy list query, C5.3).
    pub db_read: PgPool,
    /// Multiplexed Redis connection for the jti revocation blocklist (AuthUser).
    pub redis_conn: redis::aio::MultiplexedConnection,
    /// Multiplexed Redis connection used to PUBLISH chat broadcasts (`chat:{conversation_id}`).
    pub pubsub_conn: redis::aio::MultiplexedConnection,
    /// Redis client a WS session opens a dedicated SUBSCRIBER on (`psubscribe chat:*`).
    pub pubsub_client: redis::Client,
    pub jwt_config: JwtConfig,
    /// Service-JWT decoding key for the `/internal/*` surface (booking pushes request status).
    pub service_decoding_key: DecodingKey,
    /// S3/MinIO client (attachment upload + presigned download).
    pub s3: S3Client,
}

impl HasJwtSecret for AppState {
    fn jwt_secret(&self) -> &str {
        &self.jwt_config.secret
    }
    fn decoding_key(&self) -> &DecodingKey {
        &self.jwt_config.decoding_key
    }
    fn redis_conn(&self) -> &redis::aio::MultiplexedConnection {
        &self.redis_conn
    }
}

impl HasServiceJwt for AppState {
    fn service_decoding_key(&self) -> &DecodingKey {
        &self.service_decoding_key
    }
}

/// Capability seam for the CLIENT-facing chat handlers (REST + WS). Mounting handlers over a
/// trait (not the concrete [`AppState`]) lets tests exercise auth + IDOR + read-only with a
/// lightweight state (no live S3/NATS).
pub trait ChatDeps: HasJwtSecret + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
    fn db_read(&self) -> &PgPool;
    fn pubsub_conn(&self) -> &redis::aio::MultiplexedConnection;
    fn pubsub_client(&self) -> &redis::Client;
    fn s3(&self) -> &S3Client;
}

impl ChatDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
    fn db_read(&self) -> &PgPool {
        &self.db_read
    }
    fn pubsub_conn(&self) -> &redis::aio::MultiplexedConnection {
        &self.pubsub_conn
    }
    fn pubsub_client(&self) -> &redis::Client {
        &self.pubsub_client
    }
    fn s3(&self) -> &S3Client {
        &self.s3
    }
}

/// Capability seam for the service-JWT'd INTERNAL surface (booking → request-status push). Split
/// from [`ChatDeps`] so the internal guard is testable without Redis/S3 (mirrors profile).
pub trait ChatInternalDeps: HasServiceJwt + Clone + Send + Sync + 'static {
    fn db(&self) -> &PgPool;
}

impl ChatInternalDeps for AppState {
    fn db(&self) -> &PgPool {
        &self.db
    }
}
