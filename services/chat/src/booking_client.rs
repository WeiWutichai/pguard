//! booking-client adapter — the cross-service read that makes a conversation's identity
//! AUTHORITATIVE (not client-supplied).
//!
//! chat owns messaging but NOT bookings (booking). When a client asks to create a
//! booking-scoped conversation it supplies only a `request_id`; chat MINTS a short-lived
//! service-JWT (`encode_service_jwt("chat", ...)`) and GETs booking's
//! `GET /internal/bookings/{id}` to learn the AUTHORITATIVE customer/guard/status — never
//! trusting the client's `participants`/`request_status`. This closes the IDOR where any user
//! could fabricate a conversation with any victim's `user_id`, inject display text into the
//! victim's list, or set `request_status='accepted'` to bypass the read-only gate.
//!
//! A trait ([`BookingReader`]) decouples the handler from `reqwest` so authz tests are
//! hermetic. Mirrors calling/rating `booking_client`.

use jsonwebtoken::EncodingKey;
use serde::Deserialize;
use uuid::Uuid;

use shared::error::AppError;
use shared::service_jwt::encode_service_jwt;

/// The authoritative subset of a booking chat needs to build a trustworthy conversation:
/// who the parties are (`customer_id`/`guard_id`) and the lifecycle `status` (drives the
/// read-only gate). Mirrors booking's `InternalBooking` projection; chat deserializes only the
/// fields it reads (the extra money fields in the projection are ignored).
#[derive(Debug, Clone, Deserialize)]
pub struct InternalBooking {
    #[allow(dead_code)] // present in the projection; chat keys off request_id, not booking.id
    pub id: Uuid,
    pub customer_id: Uuid,
    pub guard_id: Option<Uuid>,
    pub status: String,
}

#[derive(Debug, Deserialize)]
struct BookingEnvelope {
    data: Option<InternalBooking>,
}

#[allow(async_fn_in_trait)] // internal trait, never dyn.
pub trait BookingReader: Send + Sync {
    async fn get_booking(&self, booking_id: Uuid) -> Result<InternalBooking, AppError>;
}

/// Mints service-JWTs and GETs booking's `/internal/bookings/{id}`. Cloneable (held in
/// `AppState`); `reqwest::Client` is internally ref-counted + connection-pooled.
#[derive(Clone)]
pub struct HttpBookingReader {
    http: reqwest::Client,
    /// Base URL of the booking service (no trailing slash).
    booking_url: String,
    /// Service-JWT signing key (shared `SERVICE_JWT_SECRET`).
    service_encoding_key: EncodingKey,
    /// Service-token TTL (seconds) — short-lived, per call.
    service_ttl_secs: i64,
}

impl HttpBookingReader {
    pub fn new(
        http: reqwest::Client,
        booking_url: String,
        service_encoding_key: EncodingKey,
        service_ttl_secs: i64,
    ) -> Self {
        Self {
            http,
            booking_url: booking_url.trim_end_matches('/').to_string(),
            service_encoding_key,
            service_ttl_secs,
        }
    }
}

impl BookingReader for HttpBookingReader {
    async fn get_booking(&self, booking_id: Uuid) -> Result<InternalBooking, AppError> {
        let token = encode_service_jwt("chat", &self.service_encoding_key, self.service_ttl_secs)?;
        let url = format!("{}/internal/bookings/{booking_id}", self.booking_url);
        let resp = self
            .http
            .get(&url)
            .headers(observability::trace_headers())
            .header("Authorization", format!("Bearer {token}"))
            .send()
            .await
            .map_err(|e| {
                tracing::warn!("booking internal read transport error: {e}");
                AppError::Internal("Booking lookup failed".to_string())
            })?;

        let status = resp.status();
        // 404 → no such booking: surface NotFound so the handler can deny without leaking which
        // request_ids exist (a non-party and a missing booking both get denied).
        if status == reqwest::StatusCode::NOT_FOUND {
            return Err(AppError::NotFound("Booking not found".to_string()));
        }
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_else(|_| "unknown".to_string());
            tracing::warn!("booking internal read returned {status}: {body}");
            return Err(AppError::Internal("Booking lookup failed".to_string()));
        }
        let envelope: BookingEnvelope = resp.json().await.map_err(|e| {
            tracing::warn!("booking internal read decode error: {e}");
            AppError::Internal("Booking lookup failed".to_string())
        })?;
        envelope
            .data
            .ok_or_else(|| AppError::Internal("Booking lookup returned no data".to_string()))
    }
}
