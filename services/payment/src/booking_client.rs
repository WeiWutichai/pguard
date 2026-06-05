//! booking-client adapter — the cross-service read the money path verifies against.
//!
//! The payment service NEVER trusts client-supplied customer/guard/status for the charge
//! decision (CLAUDE.md money rules). Instead it MINTS a short-lived service-JWT
//! (`encode_service_jwt("payment", ...)`) and GETs booking's `/internal/bookings/{id}`,
//! whose `ServiceCaller` guard validates the token. The returned `{ customer_id, guard_id,
//! status, hours }` is authoritative.
//!
//! A trait ([`BookingReader`]) decouples the handlers from `reqwest` so router tests are
//! hermetic (no live booking service).

use jsonwebtoken::EncodingKey;
use serde::Deserialize;
use uuid::Uuid;

use shared::error::AppError;
use shared::service_jwt::encode_service_jwt;

use crate::models::InternalBooking;

/// Local deserialize-side mirror of the `{ success, data }` envelope. `shared::models::
/// ApiResponse` is `Serialize`-only (it is the producer type), so we decode into this.
#[derive(Debug, Deserialize)]
struct BookingEnvelope {
    data: Option<InternalBooking>,
}

/// Port: read the authoritative booking for a money decision. Implemented by
/// [`HttpBookingReader`] (real) and a stub in tests.
#[allow(async_fn_in_trait)] // internal trait, never dyn — no Send-bound surprises.
pub trait BookingReader: Send + Sync {
    /// Fetch `{ id, customer_id, guard_id, status, hours }` for `booking_id`, or an error
    /// (NotFound mapped from booking's 404; generic Internal on transport failure).
    async fn get_booking(&self, booking_id: Uuid) -> Result<InternalBooking, AppError>;
}

/// Real reader: mints a service-JWT per call and GETs booking's internal read.
#[derive(Clone)]
pub struct HttpBookingReader {
    http: reqwest::Client,
    /// Base URL of the booking service, e.g. `http://booking:3005` (no trailing slash).
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
        // MINT the service-JWT that booking's ServiceCaller guard validates.
        let token =
            encode_service_jwt("payment", &self.service_encoding_key, self.service_ttl_secs)?;

        let url = format!("{}/internal/bookings/{booking_id}", self.booking_url);
        let resp = self
            .http
            .get(&url)
            .headers(observability::trace_headers()) // continue the trace across the hop
            .header("Authorization", format!("Bearer {token}"))
            .send()
            .await
            .map_err(|e| {
                // Generic outward error — never leak the upstream URL/transport detail.
                tracing::warn!("booking internal read transport error: {e}");
                AppError::Internal("Booking lookup failed".to_string())
            })?;

        let status = resp.status();
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
