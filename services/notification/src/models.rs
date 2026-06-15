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

// ----- Broadcast (admin bulk-send) -----

/// Broadcast target audience. Plain serde enum (like [`NotificationType`]); the DB column is
/// the Postgres enum `notification.broadcast_audience`, written via a `::` cast + read back as
/// text. `as_db_str` is also the value sent to profile's `/internal/profiles/recipients`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Audience {
    All,
    Guards,
    Customers,
}

impl Audience {
    pub fn as_db_str(self) -> &'static str {
        match self {
            Audience::All => "all",
            Audience::Guards => "guards",
            Audience::Customers => "customers",
        }
    }
}

/// Broadcast lifecycle. DB column `notification.broadcast_status`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BroadcastStatus {
    Draft,
    Scheduled,
    Sent,
}

impl BroadcastStatus {
    pub fn as_db_str(self) -> &'static str {
        match self {
            BroadcastStatus::Draft => "draft",
            BroadcastStatus::Scheduled => "scheduled",
            BroadcastStatus::Sent => "sent",
        }
    }
}

/// How a freshly composed broadcast should be dispatched.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BroadcastMode {
    /// Fan out immediately (status → sent).
    Now,
    /// Persist as an editable draft (no send).
    Draft,
    /// Persist for a future `scheduled_at` (the scheduler fires it).
    Scheduled,
}

/// Compose a broadcast. `mode` selects send-now / save-draft / schedule.
#[derive(Debug, Deserialize)]
pub struct CreateBroadcastRequest {
    pub audience: Audience,
    pub title: String,
    pub body: String,
    /// Defaults to `system` when omitted.
    #[serde(default)]
    pub notification_type: Option<NotificationType>,
    pub mode: BroadcastMode,
    /// Required when `mode = scheduled` (must be in the future).
    pub scheduled_at: Option<DateTime<Utc>>,
}

/// Edit an existing DRAFT broadcast (all fields optional — COALESCE semantics in the repo).
#[derive(Debug, Deserialize)]
pub struct UpdateBroadcastRequest {
    pub audience: Option<Audience>,
    pub title: Option<String>,
    pub body: Option<String>,
    pub notification_type: Option<NotificationType>,
    pub scheduled_at: Option<DateTime<Utc>>,
}

/// Query for the broadcast history list.
#[derive(Debug, Deserialize)]
pub struct ListBroadcastsQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// A broadcast campaign row as returned to the admin UI. Enum columns are read as text (DB
/// enum cast) so the read path needs no enum decoding.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct BroadcastResponse {
    pub id: Uuid,
    pub audience: String,
    pub title: String,
    pub body: String,
    pub notification_type: String,
    pub status: String,
    pub scheduled_at: Option<DateTime<Utc>>,
    pub recipient_count: i32,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub sent_at: Option<DateTime<Utc>>,
}

/// Recipient totals per audience for the composer's audience picker.
#[derive(Debug, Serialize)]
pub struct AudienceCountsResponse {
    pub all: i64,
    pub guards: i64,
    pub customers: i64,
}

// ----- Automation rules (admin "automation" surface) -----

/// An admin automation rule (`when trigger [if condition] then action` + enable toggle).
/// AUTHORING/storage only — a stored rule does not yet fire (live execution is a follow-up).
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct AutomationRule {
    pub id: Uuid,
    pub trigger_key: String,
    pub condition_text: Option<String>,
    pub action_key: String,
    pub is_enabled: bool,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Create an automation rule. `trigger_key`/`action_key` are validated against a fixed set.
#[derive(Debug, Deserialize)]
pub struct CreateRuleRequest {
    pub trigger_key: String,
    #[serde(default)]
    pub condition_text: Option<String>,
    pub action_key: String,
    #[serde(default)]
    pub is_enabled: Option<bool>,
}

/// Update an automation rule — all fields optional (COALESCE; the common edit is the toggle).
#[derive(Debug, Deserialize)]
pub struct UpdateRuleRequest {
    pub trigger_key: Option<String>,
    pub condition_text: Option<String>,
    pub action_key: Option<String>,
    pub is_enabled: Option<bool>,
}
