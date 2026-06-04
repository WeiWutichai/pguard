//! DTOs for the notification service (transport shapes). Pure data — no I/O.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Notification category. A plain serde enum (deliberately NOT `sqlx::Type`): the DB
/// column is the Postgres enum `notification.notification_type`; `repo` binds
/// [`NotificationType::as_db_str`] with a `::notification.notification_type` cast and
/// reads the column back as text. This keeps `domain` free of any DB derives.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NotificationType {
    BookingCreated,
    GuardAssigned,
    GuardEnRoute,
    GuardArrived,
    BookingCompleted,
    BookingCancelled,
    ChatMessage,
    System,
}

impl NotificationType {
    /// The snake_case label matching the Postgres enum variant.
    pub fn as_db_str(self) -> &'static str {
        match self {
            NotificationType::BookingCreated => "booking_created",
            NotificationType::GuardAssigned => "guard_assigned",
            NotificationType::GuardEnRoute => "guard_en_route",
            NotificationType::GuardArrived => "guard_arrived",
            NotificationType::BookingCompleted => "booking_completed",
            NotificationType::BookingCancelled => "booking_cancelled",
            NotificationType::ChatMessage => "chat_message",
            NotificationType::System => "system",
        }
    }
}

// ----- Requests -----

#[derive(Debug, Deserialize)]
pub struct RegisterTokenRequest {
    pub token: String,
    pub device_type: String,
}

#[derive(Debug, Deserialize)]
pub struct DeleteTokenRequest {
    pub token: String,
}

#[derive(Debug, Deserialize)]
pub struct SendNotificationRequest {
    pub user_id: Uuid,
    pub title: String,
    pub body: String,
    pub notification_type: NotificationType,
    pub payload: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
pub struct ListNotificationsQuery {
    pub unread_only: Option<bool>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    /// Filter by target role (guard/customer) stored in `payload->>'target_role'`.
    pub role: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct RoleQuery {
    pub role: Option<String>,
}

// ----- Responses -----

/// A notification row as returned to clients. `notification_type` is read as text
/// (the DB enum cast to text) so the read path needs no enum decoding.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct NotificationLogResponse {
    pub id: Uuid,
    pub user_id: Uuid,
    pub title: String,
    pub body: String,
    pub notification_type: String,
    pub payload: Option<serde_json::Value>,
    pub is_read: bool,
    pub sent_at: DateTime<Utc>,
    pub read_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
pub struct UnreadCountResponse {
    pub count: i64,
}
