-- pguard payment-service — STREAM ② ยอดที่โดนหักเข้าระบบ: record the BILLED-BUT-NEVER-COLLECTED
-- part of a settled job, and take it OUT of the amount the sweep transfers.
--
-- THE DEFECT THIS FIXES. `domain::settlement::split` computes
--     uncollected = final_amount + refunded − (amount + overpaid_amount)
-- which is non-zero exactly when the completion reconcile took its `Extra` arm: the settled bill came
-- out ABOVE the pre-payment (a tip added after the customer paid, or a `base_fee` corrected between
-- charge and reconcile) and the delta was NEVER CAPTURED — `repo::reconcile_on_completion` says so in
-- as many words ("a real gateway would capture the extra here").
--
-- Until this migration the platform's cut was computed off the SETTLED BILL regardless, so the `OAT`
-- file moved baht into the company revenue account that the customer never transferred. The account
-- it moves them OUT of is the one that also holds:
--   * the VAT owed to the Revenue Department (remitted via ภ.พ.30), and
--   * the guard income not yet paid out (stream ③).
-- An over-sweep therefore draws down precisely the money that is not ours, and the shortfall
-- surfaces later as a tax liability or a payout file that cannot be funded.
--
-- THE FIX, in three places that have to agree: the pure split now DEDUCTS `uncollected` from
-- `platform_cut()`, this column records it per job so the ledger can still explain the number, and
-- the item CHECK below is rewritten so `amount` is the SIGNED total the file actually carried.
--
-- WHY THE WHOLE SHORTFALL LANDS ON THE PLATFORM'S SHARE rather than being pro-rated across the
-- components: the guard is paid their entire `income` and the Revenue Department is owed the entire
-- `vat_amount` whatever the customer transferred. Pro-rating would shave the guard's pay and the tax
-- liability to cover a customer's unpaid bill, and would make `commission` stop meaning "the
-- commission deducted from this guard" — the number `payout_batch_items` was built from.
--
-- NO BACKFILL IS POSSIBLE OR NEEDED. Existing `deduction_batch_items` rows record files that were
-- ALREADY GENERATED and (perhaps) already uploaded: their `amount` is what the bank actually moved,
-- and rewriting it would make the ledger disagree with the transfer it justifies. `DEFAULT 0` is
-- therefore the honest value for history — those rows say "nothing was recorded as uncollected",
-- which is exactly true of a file written before this column existed. Any over-sweep already banked
-- is an accounting correction, not a migration.
--
-- Per-service schema ownership: ONLY payment writes schema `payment`. NO cross-service FKs.
-- All money columns are NUMERIC (never float) — exact decimal, `rust_decimal::Decimal` end-to-end.
--
-- IDEMPOTENT (CLAUDE.md): ADD COLUMN IF NOT EXISTS + DROP CONSTRAINT IF EXISTS + duplicate_object
-- catches, so applying it twice is a no-op and it is safe WITHOUT --single-transaction.

ALTER TABLE payment.deduction_batch_items
    -- What this job was BILLED but never actually collected. Non-negative and DEDUCTED from
    -- `amount`; 0 on every ordinary job (the reconcile refunded or matched, so everything billed was
    -- collected).
    ADD COLUMN IF NOT EXISTS uncollected NUMERIC(12,2) NOT NULL DEFAULT 0;

DO $$ BEGIN
    ALTER TABLE payment.deduction_batch_items
        ADD CONSTRAINT chk_deduction_items_uncollected_non_negative
            CHECK (uncollected >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- THE COMPONENTS MUST STILL SUM TO THE TOTAL — with the uncollected part SUBTRACTED, because that is
-- what the file's credit line actually carried. This replaces migration 0013's version of the same
-- CHECK; dropped by name first so a re-apply is a no-op and an older database converges.
--
-- Existing rows have `uncollected = 0`, so the new predicate is satisfied by every historical row
-- and the ALTER's validation pass cannot fail on real data.
ALTER TABLE payment.deduction_batch_items
    DROP CONSTRAINT IF EXISTS chk_deduction_items_amount_is_the_sum;
DO $$ BEGIN
    ALTER TABLE payment.deduction_batch_items
        ADD CONSTRAINT chk_deduction_items_amount_is_the_sum
            CHECK (amount = commission + cancellation_fee + tip + unpaid_guard_share
                            + rounding_adjustment - uncollected);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN payment.deduction_batch_items.uncollected IS
    'What this job was BILLED but never COLLECTED — the completion reconcile''s Extra arm records a settled bill above the pre-payment and captures nothing. DEDUCTED from `amount`: sweeping it would move baht that never arrived out of an account that also holds the Revenue Department''s VAT and the guards'' unpaid income. The whole shortfall lands here rather than being pro-rated, because the guard''s income and the VAT are owed in full whatever the customer transferred. 0 on every ordinary job.';
COMMENT ON COLUMN payment.deduction_batch_items.amount IS
    'The job''s total cut = commission + cancellation_fee + tip + unpaid_guard_share + rounding_adjustment − uncollected (a DB CHECK enforces it). SIGNED: a job billed over what was collected, or an unlucky proration rounding, nets DOWN against the rest of the sweep. Clamping it at zero per job would leave the receiving account short by exactly the clamped amount; the FILE total is what must be positive, and SCB''s ฿0.01 minimum enforces that at the credit line.';
