-- pguard notification-service — schema init (first vertical slice).
--
-- Per-service schema ownership: ONLY notification-service writes to schema `notification`
-- (CLAUDE.md "Data"). NO cross-service foreign keys — `user_id` is a bare UUID owned by
-- identity-service; integrity across boundaries is maintained via events, not FKs.
--
-- Note on indexes: these are created inline because the table is empty at creation.
-- LATER additive indexes on populated tables must use CREATE INDEX CONCURRENTLY
-- (CLAUDE.md "Data") in their own migration outside a transaction.

CREATE SCHEMA IF NOT EXISTS notification;

CREATE TYPE notification.notification_type AS ENUM (
    'booking_created',
    'guard_assigned',
    'guard_en_route',
    'guard_arrived',
    'booking_completed',
    'booking_cancelled',
    'chat_message',
    'system'
);

CREATE TABLE notification.fcm_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL,            -- owned by identity-service (no FK)
    token       TEXT        NOT NULL,
    device_type TEXT        NOT NULL,            -- ios | android | web
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, token)
);

CREATE INDEX idx_fcm_tokens_user_id ON notification.fcm_tokens (user_id);

CREATE TABLE notification.notification_logs (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID        NOT NULL,      -- owned by identity-service (no FK)
    title             TEXT        NOT NULL,
    body              TEXT        NOT NULL,
    notification_type notification.notification_type NOT NULL,
    payload           JSONB,
    is_read           BOOLEAN     NOT NULL DEFAULT FALSE,
    sent_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at           TIMESTAMPTZ
);

-- Hot paths: list + unread-count by user, newest first (v1 audit Phase 0 index gap).
CREATE INDEX idx_notification_logs_user_sent
    ON notification.notification_logs (user_id, sent_at DESC);
CREATE INDEX idx_notification_logs_user_unread
    ON notification.notification_logs (user_id)
    WHERE is_read = FALSE;
