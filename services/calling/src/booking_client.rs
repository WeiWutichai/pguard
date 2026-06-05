//! booking-client adapter — the cross-service read that authorizes a call.
//!
//! A call may only be placed between the two participants of a booking (CLAUDE.md authz /
//! IDOR): calling MINTS a short-lived service-JWT (`encode_service_jwt("calling", ...)`) and
//! GETs booking's `/internal/bookings/{id}`. The caller must be the booking's customer or
//! assigned guard; the callee is DERIVED as the other participant — never client-supplied.
//!
//! A trait ([`BookingReader`]) decouples the handlers from `reqwest` so authz tests are
//! hermetic. Mirrors payment/rating `booking_client`.

use jsonwebtoken::EncodingKey;
use serde::Deserialize;
use uuid::Uuid;

use shared::error::AppError;
use shared::service_jwt::encode_service_jwt;

use crate::models::InternalBooking;

#[derive(Debug, Deserialize)]
struct BookingEnvelope {
    data: Option<InternalBooking>,
}

#[allow(async_fn_in_trait)] // internal trait, never dyn.
pub trait BookingReader: Send + Sync {
    async fn get_booking(&self, booking_id: Uuid) -> Result<InternalBooking, AppError>;
}

#[derive(Clone)]
pub struct HttpBookingReader {
    http: reqwest::Client,
    booking_url: String,
    service_encoding_key: EncodingKey,
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
        let token =
            encode_service_jwt("calling", &self.service_encoding_key, self.service_ttl_secs)?;
        let url = format!("{}/internal/bookings/{booking_id}", self.booking_url);
        let resp = self
            .http
            .get(&url)
            .header("Authorization", format!("Bearer {token}"))
            .send()
            .await
            .map_err(|e| {
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
