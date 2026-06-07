-- pguard identity-service — event consumer idempotency ledger (approval → login).
--
-- identity consumes `pguard.events.user.approved` (emitted by profile when an admin approves a
-- guard) and flips its OWN `users.approval_status` to 'approved' so the account can log in —
-- closing the loop without a cross-schema write. JetStream is at-least-once, so the consumer
-- dedupes on `event_id` (same pattern as payment/notification.processed_events): claim the id +
-- flip the column in ONE transaction, so a redelivered event is a safe no-op.
CREATE TABLE identity.processed_events (
    event_id     UUID PRIMARY KEY,                   -- dedupe key (at-least-once delivery)
    event_type   TEXT        NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
