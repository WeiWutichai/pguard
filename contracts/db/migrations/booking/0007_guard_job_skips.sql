-- pguard booking-service — per-guard job SKIP (server-tracked "ข้าม / pass on this job").
--
-- v1/pre-fix, a guard's "skip" of an OPEN offer was a client-only local dismiss: it evaporated on
-- refresh (and never crossed to another device), so the skipped job kept reappearing in discovery.
-- This table persists a guard's decision to pass on a specific open booking. Discovery
-- (`list_open_bookings`) excludes a booking a guard has skipped, WITHOUT cancelling it — the job
-- stays `requested`/open for OTHER guards to claim. `(guard_id, booking_id)` PK makes the skip
-- idempotent; the FK + ON DELETE CASCADE cleans it up if the booking is deleted.

CREATE TABLE IF NOT EXISTS booking.guard_job_skips (
    guard_id   uuid        NOT NULL,
    booking_id uuid        NOT NULL REFERENCES booking.bookings(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (guard_id, booking_id)
);

-- Discovery filters open jobs by the acting guard, so index the guard side of the skip set.
CREATE INDEX IF NOT EXISTS idx_guard_job_skips_guard ON booking.guard_job_skips (guard_id);
