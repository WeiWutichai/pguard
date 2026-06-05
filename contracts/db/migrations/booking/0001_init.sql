-- pguard booking-service — schema init (Phase 1: producer side of the decoupling).
--
-- Per-service schema ownership: ONLY booking-service writes to schema `booking`
-- (CLAUDE.md "Data"). NO cross-service foreign keys — `customer_id` / `guard_id` are
-- bare UUIDs owned by identity-service; integrity across boundaries is maintained via
-- events, not FKs.
--
-- This closes Phase 1's producer half: booking persists a status change AND an outbox
-- row in ONE transaction (CLAUDE.md "Cross-tx consistency: transactional outbox"), and a
-- background relay publishes the outbox rows to NATS so the notification consumer (built
-- in the notification slice) receives them.
--
-- Note on indexes: created inline because the tables are empty at creation. LATER
-- additive indexes on populated tables must use CREATE INDEX CONCURRENTLY (CLAUDE.md
-- "Data") in their own migration outside a transaction.

CREATE SCHEMA IF NOT EXISTS booking;

-- Booking lifecycle. Matches the pure state machine in src/domain/state.rs.
--   requested → accepted | declined | cancelled
--   accepted  → en_route | cancelled
--   en_route  → arrived  | cancelled
--   arrived   → completed | cancelled
CREATE TYPE booking.booking_status AS ENUM (
    'requested',
    'accepted',
    'declined',
    'en_route',
    'arrived',
    'completed',
    'cancelled'
);

CREATE TABLE booking.bookings (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id  UUID                   NOT NULL,            -- owned by identity-service (no FK)
    guard_id     UUID,                                       -- set on accept (no FK)
    status       booking.booking_status NOT NULL DEFAULT 'requested',
    address      TEXT                   NOT NULL,
    scheduled_at TIMESTAMPTZ            NOT NULL,
    hours        INT                    NOT NULL,
    created_at   TIMESTAMPTZ            NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ            NOT NULL DEFAULT now()
);

-- Hot paths: list a caller's bookings (customer or assigned guard), newest first.
CREATE INDEX idx_bookings_customer ON booking.bookings (customer_id, created_at DESC);
CREATE INDEX idx_bookings_guard    ON booking.bookings (guard_id, created_at DESC);

-- Transactional outbox: the status change AND this row are written in ONE transaction,
-- so an event is never lost or emitted for a change that did not commit. A background
-- relay polls unpublished rows, publishes each to NATS (subject = topic), then stamps
-- published_at. `payload` is a fully-formed EventEnvelope (event_id, event_type,
-- occurred_at, correlation_id, payload).
CREATE TABLE booking.outbox (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic        TEXT        NOT NULL,            -- = EventEnvelope.event_type (NATS subject)
    payload      JSONB       NOT NULL,            -- the serialized EventEnvelope
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ
);

-- Relay polls only unpublished rows, oldest first.
CREATE INDEX idx_booking_outbox_unpublished
    ON booking.outbox (created_at)
    WHERE published_at IS NULL;
