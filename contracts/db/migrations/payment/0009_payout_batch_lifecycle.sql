-- pguard payment-service — GUARD PAYOUT: the batch LIFECYCLE + the one-way door it closes.
--
-- THE DEFECT THIS FIXES. `POST /admin/payouts/export` committed the per-booking paid-markers and
-- then streamed the file text ONCE, storing nothing. So a failed download, a closed tab, a proxy
-- timeout, or an SCB upload rejection left those bookings marked paid FOREVER with no copy of the
-- file that was supposed to pay them — the guards silently never get paid for that work, and the
-- only remedy is a hand-written DELETE in production. There was also no record of what was ever
-- sent to the bank.
--
-- The fix is NOT a two-phase draft (that would trade this bug for a stuck-draft one — a client that
-- dies after downloading but before confirming leaves bookings neither paid nor payable). It is:
--   (a) STORE the generated file text on the batch, so it can always be re-downloaded;
--   (b) a STATUS the admin drives as the file makes its way through SCB (generated → uploaded →
--       confirmed | rejected), so "what did we actually send, and did it land?" has an answer;
--   (c) a VOID that genuinely returns the work to the backlog (see the item flag below);
--   (d) `money_audit` — the append-only compliance record of every admin action that moves money.
--
-- Per-service schema ownership: ONLY payment writes schema `payment`. NO cross-service FKs —
-- `voided_by`/`actor`/`target_id` are bare UUIDs owned by identity/booking.
--
-- IDEMPOTENT (CLAUDE.md): ADD COLUMN IF NOT EXISTS / CREATE … IF NOT EXISTS / duplicate_object
-- catches throughout, so applying it twice is a no-op. Safe WITHOUT --single-transaction (the
-- migrator feeds the file to psql statement-by-statement); the ONE place that needs atomicity
-- (the unique-index swap) carries its own explicit BEGIN/COMMIT.

-- ── (a) payout_batches: the lifecycle columns ────────────────────────────────────────────────
-- `status` starts at 'generated' — every EXISTING row is exactly that (a file was generated and
-- handed to an admin; nothing more was ever recorded), so the DEFAULT backfills them correctly.
ALTER TABLE payment.payout_batches
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'generated';

-- The status vocabulary is closed: the pure transition table in
-- `services/payment/src/domain/batch_status.rs` is the only writer, and this CHECK is the last line
-- if anything else ever writes the column by hand.
DO $$ BEGIN
    ALTER TABLE payment.payout_batches
        ADD CONSTRAINT chk_payout_batches_status
            CHECK (status IN ('generated', 'uploaded', 'confirmed', 'rejected', 'voided'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- The EXACT bytes handed to the admin. This is what the re-download endpoint serves — not a
-- regenerated file: regenerating would pick up a changed config/rate/profile and produce a
-- DIFFERENT file under the same batch ref, which is the one thing a money record must never do.
-- Nullable because rows written before this migration have no stored copy (re-download 404s for
-- them, honestly, rather than inventing one).
ALTER TABLE payment.payout_batches ADD COLUMN IF NOT EXISTS file_text TEXT;

-- When each lifecycle step happened. Separate columns (not one `status_at`) so the history of a
-- batch survives the next transition — "uploaded at 09:12, rejected at 09:40" is the whole point.
ALTER TABLE payment.payout_batches ADD COLUMN IF NOT EXISTS uploaded_at  TIMESTAMPTZ;
ALTER TABLE payment.payout_batches ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMPTZ;
ALTER TABLE payment.payout_batches ADD COLUMN IF NOT EXISTS rejected_at  TIMESTAMPTZ;
ALTER TABLE payment.payout_batches ADD COLUMN IF NOT EXISTS voided_at    TIMESTAMPTZ;
ALTER TABLE payment.payout_batches ADD COLUMN IF NOT EXISTS voided_by    UUID;   -- acting admin, no FK
-- WHY the batch was voided (required, non-blank at the API): six months later "voided" alone tells
-- nobody whether the bank bounced it or an admin mis-clicked, and the bookings went back into the
-- payable backlog on the strength of it.
ALTER TABLE payment.payout_batches ADD COLUMN IF NOT EXISTS void_reason  TEXT;
-- Free-text note attached to the LATEST status change (e.g. the bank's rejection message).
ALTER TABLE payment.payout_batches ADD COLUMN IF NOT EXISTS status_note  TEXT;

-- `recipient_count` was written as the ITEM count (one row per BOOKING) rather than the RECIPIENT
-- count (one per GUARD): a guard paid for three finished jobs is ONE recipient and ONE TXNDET, so a
-- batch of 3 bookings for 1 guard recorded "3 recipients" while the file it describes has 1. The
-- writer is fixed in `repo::insert_payout_batch`; this converges the rows already stored. It is
-- idempotent by construction (it recomputes an exact value) and the `IS DISTINCT FROM` keeps a
-- re-apply from touching a single row.
UPDATE payment.payout_batches b
   SET recipient_count = c.n
  FROM (SELECT batch_id, count(DISTINCT guard_id) AS n
          FROM payment.payout_batch_items GROUP BY batch_id) c
 WHERE c.batch_id = b.id
   AND b.recipient_count IS DISTINCT FROM c.n::int;

-- ── (b) payout_batch_items: the flag that makes VOID actually work ───────────────────────────
-- WHY THIS FLAG IS DENORMALISED ONTO THE ITEM (do not "normalise" it away):
-- `uq_payout_batch_items_booking` was a plain UNIQUE on `booking_id`, and it is the paid-marker.
-- If voiding only flagged the BATCH, the item rows would still be there, the unique would still
-- fire, and the booking could NEVER be paid again — exactly the bug void exists to fix. Postgres
-- cannot express "unique unless the PARENT row is voided" in a partial index (index predicates see
-- one table), so the void is stamped on the ITEM and the unique becomes partial on it. History is
-- preserved either way: the item row survives, so you can still see the guard was in a voided batch.
ALTER TABLE payment.payout_batch_items ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ;

-- Swap the unique: full → partial (live items only). Wrapped in an EXPLICIT transaction because
-- these two statements must not be separated — a window with NO unique on `booking_id` is a window
-- in which two concurrent exports can both pay the same job.
--
-- NOT `CONCURRENTLY` (and matching 0007's plain index style): CONCURRENTLY cannot run inside a
-- transaction block at all, so it could not be paired atomically with the DROP — and a CONCURRENTLY
-- build that fails leaves an INVALID index behind that the `IF NOT EXISTS` on a re-apply would
-- silently skip, leaving the double-pay guard permanently off. This table holds one row per booking
-- ever paid and is written only by an admin export, so the brief lock is free.
BEGIN;
DROP INDEX IF EXISTS payment.uq_payout_batch_items_booking;
CREATE UNIQUE INDEX IF NOT EXISTS uq_payout_batch_items_booking_live
    ON payment.payout_batch_items (booking_id)
 WHERE voided_at IS NULL;
COMMIT;

-- ── (c) money_audit — the append-only compliance record ──────────────────────────────────────
-- Every admin action that MOVES MONEY (generating a payout file, walking it through the bank,
-- voiding it) writes one row here, in the same transaction as the action itself, so the record can
-- never disagree with what happened. Append-only by discipline: nothing in the service updates or
-- deletes a row. `actor`/`target_id` are bare UUIDs (no cross-service FK); `detail` is the JSONB
-- envelope of whatever the action needs to be reconstructed later (refs, totals, the void reason).
CREATE TABLE IF NOT EXISTS payment.money_audit (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor        UUID,                                          -- acting admin (bare UUID, no FK)
    action       TEXT        NOT NULL,                          -- e.g. payout_batch_exported
    target_kind  TEXT        NOT NULL,                          -- e.g. payout_batch
    target_id    UUID,                                          -- the row acted on (bare UUID)
    detail       JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The two ways the log is read: the reverse-chronological feed, and "everything ever done to THIS
-- batch".
CREATE INDEX IF NOT EXISTS idx_money_audit_created ON payment.money_audit (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_money_audit_target  ON payment.money_audit (target_kind, target_id);

COMMENT ON TABLE  payment.money_audit IS
    'Append-only compliance log of admin actions that move money (payout export / status change / void). Written in the same transaction as the action.';
COMMENT ON COLUMN payment.payout_batches.file_text IS
    'The EXACT SCB file text handed to the admin, stored so it can be re-downloaded. Never regenerated: a regenerated file could differ (config/rate/profile changed) under the same batch ref. NULL for batches generated before this column existed.';
COMMENT ON COLUMN payment.payout_batches.status IS
    'Lifecycle: generated → uploaded → confirmed | rejected; generated/uploaded/rejected → voided. confirmed + voided are TERMINAL. The transition table lives in domain/batch_status.rs.';
COMMENT ON COLUMN payment.payout_batches.recipient_count IS
    'How many GUARDS the file pays (= TXNDET lines), NOT how many bookings — a guard with three finished jobs is one recipient.';
COMMENT ON COLUMN payment.payout_batch_items.voided_at IS
    'Set on EVERY item when its batch is voided. Denormalised deliberately: the paid-marker unique is PARTIAL on this column (Postgres cannot make a unique depend on the parent row), so voiding returns the booking to the payable backlog while keeping the history.';
