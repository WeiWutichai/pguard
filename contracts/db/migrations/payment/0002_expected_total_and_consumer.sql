-- pguard payment-service — Phase 3: authoritative total + refund workflow + event consumer.
--
-- (1) `expected_total` records the SERVER-computed authoritative total at charge time
--     (`base_fee × hours × guard_count + tip`, all from the booking's authoritative read).
--     The charge handler rejects any `amount` below it — a client can never undercut the
--     price (CLAUDE.md money rules). Exact decimal, never float.
--
-- (2) `refund_status` drives the admin refund workflow (mirrors v1 migration 042): set to
--     'pending' when a proration leaves a refund owed, marked 'processed' by an admin later.
--
-- (3) `processed_events` is the idempotency ledger for the `booking.completed` consumer.
--     JetStream is at-least-once, so the consumer dedupes on `event_id` (same pattern as
--     notification.processed_events): claim the id + finalize proration in ONE transaction,
--     so a redelivered completion never double-applies a refund.
--
-- Dev note: payment.payments is empty (no production data), so ADD COLUMN is instant.

ALTER TABLE payment.payments
    ADD COLUMN expected_total NUMERIC(12,2),   -- server-computed authoritative total at charge time
    ADD COLUMN refund_status  TEXT;            -- NULL | 'pending' | 'processed'

ALTER TABLE payment.payments
    ADD CONSTRAINT chk_payments_refund_status
        CHECK (refund_status IS NULL OR refund_status IN ('pending', 'processed'));

-- Idempotency ledger: the booking.completed consumer claims each event_id exactly once.
CREATE TABLE payment.processed_events (
    event_id     UUID PRIMARY KEY,                   -- dedupe key (at-least-once delivery)
    event_type   TEXT        NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
