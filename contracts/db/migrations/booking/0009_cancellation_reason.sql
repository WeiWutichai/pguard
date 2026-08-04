-- pguard booking-service — WHY a booking ended without work: the mandatory cancellation reason.
--
-- Both terminal "the job did not happen" transitions now capture a reason:
--   * `cancel`  (customer, PRE-ARRIVAL: requested/accepted/en_route → cancelled)
--   * `decline` (the ASSIGNED guard withdrawing pre-arrival: accepted/en_route → declined)
-- Until now a cancelled/declined booking was indistinguishable from any other — support could
-- not tell a customer who changed their mind from a guard who never showed, and the refund
-- (payment's cancellation consumer full-refunds a paid pre-arrival cancel) carried no cause.
--
-- `cancellation_reason` stores a STABLE CODE, never localized text — the app/web-admin render
-- the Thai/English label from the code, so re-wording a label never rewrites history and a
-- report can GROUP BY it. The code sets are per-endpoint and DIFFERENT (enforced in the
-- service's pure domain layer, `domain::cancellation`, NOT by a DB enum — the sets are
-- product copy that will churn, and a Postgres enum would need a migration per tweak):
--   customer cancel : changed_plan | mistake | not_needed | other
--   guard decline   : emergency | sick | cannot_reach | other
--
-- `cancellation_note` is the OPTIONAL free-text elaboration — REQUIRED by the service when the
-- reason is 'other' (a bare "other" tells support nothing), otherwise the customer/guard may
-- add colour or leave it out. It is echoed back on every booking read, hence the length cap.
--
-- Both columns are nullable, no default. NULL means "no reason recorded", never "unknown code":
--   * every booking cancelled/declined BEFORE this migration (pre-migration rows);
--   * a booking that never reached a terminal did-not-happen state at all (the common case —
--     the columns stay NULL for the whole happy path).
--
-- Statements are individually idempotent (IF NOT EXISTS / the DO-block duplicate_object catch)
-- — migrate.sh applies files via psql WITHOUT --single-transaction (statement auto-commit), and
-- a mid-file failure commits earlier statements without a ledger row (see
-- tooling/scripts/migrate.sh).

ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;  -- stable code, never localized text (NULL = no reason recorded)
ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS cancellation_note   TEXT;  -- optional free text (REQUIRED by the service when reason = 'other')

-- Length cap on the free text, in the style of chk_payments_refund_status. The service caps the
-- note at 500 CHARACTERS (`.chars().count()` — Thai text is multi-byte, so bytes would silently
-- shrink the real limit); `char_length()` is the Postgres counterpart, so the DB backstop and the
-- domain validator agree exactly. Postgres has no `ADD CONSTRAINT IF NOT EXISTS`, so the
-- duplicate_object catch is what makes this statement independently re-runnable.
DO $$
BEGIN
    ALTER TABLE booking.bookings
        ADD CONSTRAINT chk_bookings_cancellation_note_len
        CHECK (cancellation_note IS NULL OR char_length(cancellation_note) <= 500);
EXCEPTION
    WHEN duplicate_object THEN NULL;  -- already applied
END $$;
