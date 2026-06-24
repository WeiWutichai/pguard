-- pguard chat-service — the inbound call-summary consumer's idempotency ledger.
--
-- Chat was a PURE PRODUCER until now (only the outbox relay → chat.message_sent). This migration
-- adds chat's FIRST inbound NATS JetStream consumer support: a call-summary line is posted into
-- the booking's conversation when a call terminates (`pguard.events.calling.ended` /
-- `.rejected`), so the thread shows "audio call · completed · 2m" etc.
--
-- The summary is a SERVER-GENERATED `system` message (clients can no longer mark a message as
-- `system` — that is the security fix: a participant could otherwise silence the victim's "new
-- message" push, which notification suppresses for system rows). The insert goes through the SAME
-- transactional-outbox path as a normal message, so notification still (correctly) SKIPS the push
-- for the system row.
--
--   chat.processed_events — the idempotency ledger (mirrors booking.processed_events). Keyed by
--   the envelope's `event_id`, claimed in the SAME transaction that inserts the summary message +
--   its outbox row, so a JetStream redelivery (at-least-once) can NEVER double-post a summary.
--   The consumer INSERTs ON CONFLICT DO NOTHING and only acts on a won claim.
--
-- Per-service schema ownership: only chat-service writes schema `chat` (CLAUDE.md "Data").
-- Dev note: this is an additive CREATE TABLE on an empty/new table — safe + instant.

CREATE TABLE IF NOT EXISTS chat.processed_events (
    event_id     UUID PRIMARY KEY,            -- EventEnvelope.event_id (dedupe key)
    event_type   TEXT        NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
