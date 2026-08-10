-- pguard booking-service — the platform's cut and the customer's no-show fee, PER SERVICE.
--
-- Two new money knobs on the admin-curated catalog (migration 0005), and their SNAPSHOT on
-- every booking created from it:
--
--   commission_percent — the platform's cut of ONE guard's pay, in percent. It is deducted
--     from the GUARD, never added to the customer: the customer pays exactly the same either
--     way, and the guard receives `guard_gross − guard_gross × commission_percent / 100`.
--     Per SERVICE, because a ฿230/h event-crowd job and a ฿500/h armed escort do not carry the
--     same margin. 0 (the default) = the platform takes nothing, i.e. today's behaviour, so
--     applying this migration alone changes nobody's pay.
--
--   cancellation_fee — a FLAT ฿ amount kept when the CUSTOMER cancels before work starts.
--     Flat, not a percentage: the guard has already been dispatched, and what it compensates is
--     the wasted trip, not the size of the job. "Take what is there, never leave a debt" —
--     the service charges `min(cancellation_fee, amount_actually_paid)`, so an unpaid booking
--     costs the customer nothing and a partly-paid one is never driven negative. A GUARD
--     withdrawing (`declined`) is not the customer's fault and still refunds in full.
--
-- WHY THE SNAPSHOT ON `bookings`
-- The catalog is editable at any time by an admin. Without a snapshot, raising the commission
-- next week would silently restate what a guard earned on a job booked (and worked, and paid)
-- today — the money of a settled booking would follow a row the guard never agreed to. So the
-- booking COPIES both values at creation and the money path reads the copy, never the catalog.
-- Editing the catalog therefore only ever affects bookings created AFTER the edit.
--
-- On `service_catalog` the columns are NOT NULL DEFAULT 0 — every catalog row has an
-- authoritative number, and the pre-existing rows inherit the no-op value.
--
-- On `bookings` they are NULLABLE, and NULL means exactly one thing: a booking created BEFORE
-- this migration, which was never quoted a commission or a fee. Readers treat NULL as 0 (no
-- cut, no fee) — the same no-op. It is NOT "unknown, ask the catalog": going back to the
-- catalog is precisely what the snapshot exists to prevent. Bookings created from here on
-- always carry real numbers, including the literal 0/0 written when the customer picked no
-- catalog service at all (the back-compat path, where `base_fee` falls to the column DEFAULT).
--
-- Scales match the money already in the schema: NUMERIC(12,2) for ฿ amounts (like `base_fee`,
-- `tip`), NUMERIC(5,2) for the percent — two decimals of a percent is finer than any commission
-- anyone will negotiate, and 5 digits total leaves the 0..100 range room to spare.
--
-- Statements are individually idempotent (IF NOT EXISTS / the DO-block duplicate_object catch)
-- — migrate.sh applies files via psql WITHOUT --single-transaction (statement auto-commit), and
-- a mid-file failure commits earlier statements without a ledger row (see
-- tooling/scripts/migrate.sh).

-- ----- the catalog knobs (admin-editable; NOT NULL, 0 = today's behaviour) -----

ALTER TABLE booking.service_catalog ADD COLUMN IF NOT EXISTS commission_percent NUMERIC(5,2)  NOT NULL DEFAULT 0;  -- platform's cut of the GUARD's pay, %
ALTER TABLE booking.service_catalog ADD COLUMN IF NOT EXISTS cancellation_fee   NUMERIC(12,2) NOT NULL DEFAULT 0;  -- flat ฿ kept on a customer pre-arrival cancel

-- ----- the per-booking snapshot (NULL = pre-migration booking; readers treat it as 0) -----

ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS commission_percent NUMERIC(5,2);   -- copied from the catalog at creation, never re-read from it
ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS cancellation_fee   NUMERIC(12,2);  -- copied from the catalog at creation, never re-read from it

-- Range backstops, in the style of chk_bookings_cancellation_note_len. The service validates
-- both in its pure domain layer (`domain::pricing`) and these CHECKs are the DB's independent
-- guarantee that no path — a manual admin UPDATE, a future importer — can persist a negative
-- fee or a commission above 100% (which would pay a guard a negative wage). Postgres has no
-- `ADD CONSTRAINT IF NOT EXISTS`, so the duplicate_object catch is what makes each statement
-- independently re-runnable.
DO $$
BEGIN
    ALTER TABLE booking.service_catalog
        ADD CONSTRAINT chk_service_catalog_commission_percent
        CHECK (commission_percent >= 0 AND commission_percent <= 100);
EXCEPTION
    WHEN duplicate_object THEN NULL;  -- already applied
END $$;

DO $$
BEGIN
    ALTER TABLE booking.service_catalog
        ADD CONSTRAINT chk_service_catalog_cancellation_fee
        CHECK (cancellation_fee >= 0);
EXCEPTION
    WHEN duplicate_object THEN NULL;  -- already applied
END $$;

-- The booking copies are nullable, so each CHECK passes NULL through explicitly (a bare
-- comparison would already be NULL-tolerant, but spelling it out documents that NULL is a
-- LEGAL, expected value here — the pre-migration rows — not an oversight).
DO $$
BEGIN
    ALTER TABLE booking.bookings
        ADD CONSTRAINT chk_bookings_commission_percent
        CHECK (commission_percent IS NULL OR (commission_percent >= 0 AND commission_percent <= 100));
EXCEPTION
    WHEN duplicate_object THEN NULL;  -- already applied
END $$;

DO $$
BEGIN
    ALTER TABLE booking.bookings
        ADD CONSTRAINT chk_bookings_cancellation_fee
        CHECK (cancellation_fee IS NULL OR cancellation_fee >= 0);
EXCEPTION
    WHEN duplicate_object THEN NULL;  -- already applied
END $$;
