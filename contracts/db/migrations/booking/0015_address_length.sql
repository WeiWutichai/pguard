-- pguard booking-service — bound the customer-controlled booking address (deep-review MED #10).
--
-- `address` had no length cap: an authenticated customer could POST a ~1 MB TEXT address (under
-- the gateway's 1 MiB body cap), which then fanned out — persisted per booking, embedded verbatim
-- in the `booking.requested` outbox/NATS event, and re-served in full on GET /bookings/open to
-- EVERY discovering guard (up to the house page limit). The service already caps the check-in note
-- at 500/2000 chars for exactly this reason (`chk_bookings_cancellation_note_len`); the
-- customer-controlled address had no cap at all. The service now rejects an over-long/empty
-- address with a typed 400 in `create_booking`; this is the matching DB backstop so the invariant
-- holds even if a future write path forgets the handler check.
--
-- 512 CHARACTERS (`char_length`, the Postgres counterpart to the service's `.chars().count()` —
-- Thai text is multi-byte, so a byte cap would silently shrink the real limit for Thai users). A
-- real street address is well under this; the cap only rejects abuse. Existing rows are short, so
-- adding the CHECK does not rewrite or reject any current data.
--
-- Postgres has no `ADD CONSTRAINT IF NOT EXISTS`, so the duplicate_object catch is what makes this
-- statement independently re-runnable (mirrors chk_bookings_cancellation_note_len). migrate.sh
-- applies files via psql WITHOUT --single-transaction (statement auto-commit).

DO $$
BEGIN
    ALTER TABLE booking.bookings
        ADD CONSTRAINT chk_bookings_address_len
        CHECK (char_length(address) <= 512);
EXCEPTION
    WHEN duplicate_object THEN NULL;  -- already applied
END $$;
