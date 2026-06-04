-- pguard notification-service — event consumer support (Phase 1 / KICKOFF §2.4).
--
-- Two tables that make the NATS JetStream consumer correct under at-least-once delivery:
--   1. processed_events — idempotency ledger keyed by the envelope's event_id, so a
--      redelivered event cannot double-notify. The consumer claims the id in the SAME
--      transaction that writes the notification_logs row (atomic).
--   2. outbox — transactional outbox for anything notification itself emits. Empty for
--      now (notification is a pure consumer), but the pattern is wired so later services
--      reuse it (CLAUDE.md "Cross-tx consistency: transactional outbox").

CREATE TABLE notification.processed_events (
    event_id     UUID PRIMARY KEY,            -- EventEnvelope.event_id (dedupe key)
    event_type   TEXT        NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notification.outbox (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic        TEXT        NOT NULL,
    payload      JSONB       NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ
);

-- Relay polls only unpublished rows.
CREATE INDEX idx_outbox_unpublished
    ON notification.outbox (created_at)
    WHERE published_at IS NULL;
