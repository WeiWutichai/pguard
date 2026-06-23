-- pguard booking-service — PRE-PAY gate + the inbound event-consumer support.
--
-- v2 is PRE-PAY: after a guard ACCEPTS, the customer pays the server-computed estimate; the
-- booking only learns it is paid by CONSUMING `pguard.events.payment.completed` (no cross-service
-- write — CLAUDE.md "Inter-service comms: NATS JetStream events"). This migration adds:
--
--   1. bookings.paid_at — when payment told us the booking is paid (NULL = unpaid). The
--      `accepted → en_route` transition (and everything after, naturally) is GATED on this being
--      set: an en_route on an unpaid booking is a 409 "payment required". Nullable, no default,
--      because most lifecycle states legitimately have no payment yet.
--
--   2. booking.processed_events — the idempotency ledger for booking's NEW inbound consumer
--      (mirrors notification.processed_events). Keyed by the envelope's `event_id`, claimed in
--      the SAME transaction that stamps `paid_at`, so a JetStream redelivery (at-least-once)
--      can never re-stamp or double-process. Booking was a PURE PRODUCER until now (only the
--      outbox relay); this is its first consumer, so the ledger is introduced here.
--
-- Dev note: booking.bookings is empty (no production users — strangler-fig is discipline-only
-- here), so ADD COLUMN nullable is a safe, instant change.

ALTER TABLE booking.bookings
    ADD COLUMN paid_at TIMESTAMPTZ;   -- set by the payment.completed consumer; NULL = unpaid (en_route gate)

-- Idempotency ledger for the inbound NATS JetStream consumer (payment.completed → set paid_at).
-- One row per processed envelope; the consumer INSERTs ON CONFLICT DO NOTHING and only acts on a
-- won claim, so an at-least-once redelivery is a no-op.
CREATE TABLE booking.processed_events (
    event_id     UUID PRIMARY KEY,            -- EventEnvelope.event_id (dedupe key)
    event_type   TEXT        NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Discovery active-assignment exclusion (the fix): `available_guards` must hide a guard who
-- already holds an ACTIVE assignment (a booking in accepted/en_route/arrived/pending_completion
-- assigned to them). This partial index backs that membership lookup (`busy_guard_ids`) — only
-- the small set of in-flight assigned bookings is indexed, not the whole table.
CREATE INDEX idx_bookings_active_assignment
    ON booking.bookings (guard_id)
    WHERE guard_id IS NOT NULL
      AND status IN ('accepted', 'en_route', 'arrived', 'pending_completion');
