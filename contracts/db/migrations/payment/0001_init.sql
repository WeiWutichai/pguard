-- pguard payment-service — schema init (Phase 3: split from v1 booking god-service).
--
-- THE MONEY PATH. Per-service schema ownership: ONLY payment-service writes to schema
-- `payment` (CLAUDE.md "Data"). NO cross-service foreign keys — `booking_id`,
-- `customer_id`, `guard_id` are bare UUIDs owned by booking/identity; integrity across
-- boundaries is maintained via events + the service-JWT'd internal read, never FKs.
--
-- All money columns are NUMERIC (never float): exact decimal arithmetic. The Rust side
-- uses `rust_decimal::Decimal` end-to-end.
--
-- Idempotent charge: at most ONE completed payment per booking, enforced by a UNIQUE
-- partial index (WHERE status='completed'). A retried POST /payments cannot double-charge;
-- the handler does ON CONFLICT DO NOTHING and returns the existing completed payment.
--
-- Transactional outbox: a charge (or refund) writes the business row AND the event row in
-- ONE transaction (CLAUDE.md "Cross-tx consistency"); a background relay publishes to NATS.
--
-- Note on indexes: created inline because the tables are empty at creation. LATER additive
-- indexes on populated tables must use CREATE INDEX CONCURRENTLY (CLAUDE.md "Data").

CREATE SCHEMA IF NOT EXISTS payment;

-- Payment lifecycle. `pending` is reserved for a future two-step (authorize→capture) flow;
-- v2's simulated gateway records `completed` immediately, `refunded` once fully refunded.
CREATE TYPE payment.payment_status AS ENUM (
    'pending',
    'completed',
    'refunded'
);

CREATE TABLE payment.payments (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id     UUID                    NOT NULL,           -- owned by booking-service (no FK)
    customer_id    UUID                    NOT NULL,           -- owned by identity-service (no FK)
    guard_id       UUID,                                       -- from the booking at charge time (no FK)
    amount         NUMERIC(12,2)           NOT NULL,           -- charged amount (exact decimal)
    payment_method TEXT,
    status         payment.payment_status  NOT NULL,
    final_amount   NUMERIC(12,2),                              -- prorated amount after completion
    refund_amount  NUMERIC(12,2),                              -- amount returned to the customer
    actual_hours   NUMERIC(6,2),                               -- clamped hours actually worked
    paid_at        TIMESTAMPTZ,
    created_at     TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ             NOT NULL DEFAULT now()
);

-- IDEMPOTENCY GUARD: at most one COMPLETED payment per booking. The charge path relies on
-- this together with ON CONFLICT so a retried request returns the existing row instead of
-- inserting a second charge. (Partial: a refunded row no longer blocks a fresh charge,
-- though the v2 flow never re-charges.)
CREATE UNIQUE INDEX uq_payment_one_completed_per_booking
    ON payment.payments (booking_id)
    WHERE status = 'completed';

-- Hot path: list a caller's payments, newest first.
CREATE INDEX idx_payments_customer ON payment.payments (customer_id, created_at DESC);

-- Transactional outbox: the payment row AND this row are written in ONE transaction, so a
-- `payment.completed` / `payment.refund_processed` event is never lost or emitted for a
-- change that did not commit. A background relay polls unpublished rows, publishes each to
-- NATS (subject = topic), then stamps published_at. `payload` is a fully-formed
-- EventEnvelope (event_id, event_type, occurred_at, correlation_id, payload).
CREATE TABLE payment.outbox (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic        TEXT        NOT NULL,            -- = EventEnvelope.event_type (NATS subject)
    payload      JSONB       NOT NULL,            -- the serialized EventEnvelope
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ
);

-- Relay polls only unpublished rows, oldest first.
CREATE INDEX idx_payment_outbox_unpublished
    ON payment.outbox (created_at)
    WHERE published_at IS NULL;
