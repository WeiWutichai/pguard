-- pguard notification-service — admin broadcast campaigns (web-admin "broadcast" screen).
--
-- A broadcast is an admin-composed message fanned out to a ROLE AUDIENCE (all / guards /
-- customers). Per-recipient delivery still lands as the existing notification.notification_logs
-- rows (+ best-effort FCM push), so a recipient sees the broadcast in the same in-app feed as
-- any other notification. THIS table is the CAMPAIGN ledger — one row per composed broadcast,
-- tracking its lifecycle (draft -> scheduled -> sent) and how many recipients it reached.
--
-- Audience enumeration is CROSS-SERVICE BY DESIGN (decided 2026-06-15): notification owns no
-- user/role registry (only fcm_tokens + notification_logs, both bare user_id). To resolve
-- "all guards"/"all customers" it mints a short-lived service-JWT and calls profile's
-- `/internal/profiles/recipients?audience=…` (profile owns guard_profiles/customer_profiles).
-- See docs/PHASE-broadcast-spec.md. No cross-service FK — user_id columns are bare UUIDs.
--
-- Indexes are inline (empty table at creation). Any LATER additive index on this populated
-- table must use CREATE INDEX CONCURRENTLY in its own migration (CLAUDE.md "Data").

CREATE TYPE notification.broadcast_audience AS ENUM ('all', 'guards', 'customers');
CREATE TYPE notification.broadcast_status   AS ENUM ('draft', 'scheduled', 'sent');

CREATE TABLE notification.broadcasts (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    audience          notification.broadcast_audience NOT NULL,
    title             TEXT        NOT NULL,
    body              TEXT        NOT NULL,
    -- Reuses the existing per-notification category enum; broadcasts default to 'system'.
    notification_type notification.notification_type NOT NULL DEFAULT 'system',
    status            notification.broadcast_status   NOT NULL DEFAULT 'draft',
    -- Required when status = 'scheduled' (the scheduler fires at/after this time).
    scheduled_at      TIMESTAMPTZ,
    -- Recipients actually enqueued at send time (0 until sent).
    recipient_count   INTEGER     NOT NULL DEFAULT 0,
    created_by        UUID        NOT NULL,   -- admin user_id (owned by identity; no FK)
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at           TIMESTAMPTZ,
    -- A scheduled broadcast must carry its fire time (the scheduler keys off it).
    CONSTRAINT broadcasts_scheduled_needs_time
        CHECK (status <> 'scheduled' OR scheduled_at IS NOT NULL)
);

-- Scheduler hot path: poll only due, still-scheduled rows (partial index stays tiny).
CREATE INDEX idx_broadcasts_due
    ON notification.broadcasts (scheduled_at)
    WHERE status = 'scheduled';

-- Sent/draft history list, newest first.
CREATE INDEX idx_broadcasts_created
    ON notification.broadcasts (created_at DESC);
