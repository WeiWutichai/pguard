//! Shared application state.
//!
//! All OTP endpoints are PUBLIC (pre-auth) — there is no `AuthUser`/service-JWT extractor
//! here, so the state needs no `HasJwtSecret`/`HasServiceJwt` impl (unlike notification).
//! `jwt_config` is held only to SIGN the single-use phone-verified token issued on verify.

use std::sync::Arc;

use sqlx::PgPool;

use shared::config::JwtConfig;

use crate::config::OtpConfig;
use crate::sms::SmsSender;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Multiplexed Redis connection for captcha / cooldown / daily / lockout / jti keys.
    pub redis_conn: redis::aio::MultiplexedConnection,
    pub otp_config: OtpConfig,
    /// Used to sign (encoding_key) and self-issue the phone-verified token.
    pub jwt_config: JwtConfig,
    /// SMS port — [`crate::sms::InetSender`] in prod, `NoopSender` when `SMS_DISABLED`.
    pub sms: Arc<dyn SmsSender>,
    /// Shared HTTP client (connection reuse). The [`crate::sms::InetSender`] is built with
    /// a clone of this in `main`; the field is retained on state per the service spec so
    /// future outbound calls reuse one pool. Not yet read directly after construction.
    #[allow(dead_code)]
    pub http_client: reqwest::Client,
}
