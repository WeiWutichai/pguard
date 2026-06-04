-- pguard booking-service — Phase 3: authoritative pricing inputs + work-timing.
--
-- The money path requires the booking to carry the SERVER-OWNED pricing inputs so the
-- payment service can compute the expected total from the authoritative booking read
-- (`base_fee × hours × guard_count + tip`) instead of trusting a client-supplied amount
-- (CLAUDE.md money rules). `base_fee` is set by the system (never the client); `guard_count`
-- and `tip` are part of the customer's request but live here as the source of truth.
--
-- `work_started_at` is stamped when the assigned guard goes en_route — it is the basis for
-- the actual hours worked that the completion event carries to payment for proration
-- (mirrors v1's `started_at`; see ../guard-dispatch/services/booking/src/service.rs
-- prorate_payment_in_tx: actual_seconds = completed_at − started_at).
--
-- Dev note: booking.bookings is empty (no production users — strangler-fig is discipline-
-- only here), so ADD COLUMN ... NOT NULL DEFAULT is a safe, instant rewrite. On a populated
-- production table this would be split (add nullable → backfill → set NOT NULL).

ALTER TABLE booking.bookings
    ADD COLUMN base_fee        NUMERIC(12,2) NOT NULL DEFAULT 500.00,  -- ฿ per hour per guard (server-set)
    ADD COLUMN guard_count     INT           NOT NULL DEFAULT 1,
    ADD COLUMN tip             NUMERIC(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN work_started_at TIMESTAMPTZ;                            -- set on en_route; basis for actual worked time

-- Pricing inputs must be sane (mirror v1's guard_count 1..20 + non-negative money checks).
ALTER TABLE booking.bookings
    ADD CONSTRAINT chk_bookings_guard_count CHECK (guard_count BETWEEN 1 AND 20),
    ADD CONSTRAINT chk_bookings_base_fee_nonneg CHECK (base_fee >= 0),
    ADD CONSTRAINT chk_bookings_tip_nonneg CHECK (tip >= 0);
