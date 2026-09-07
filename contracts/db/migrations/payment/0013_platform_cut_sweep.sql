-- pguard payment-service — STREAM ② ยอดที่โดนหักเข้าระบบ: the PLATFORM-CUT sweep (SCB `OAT`)
-- plus the pricing SNAPSHOT the cut is computed from.
--
-- WHAT THIS FILE SWEEPS, AND WHAT IT MUST NEVER SWEEP. Read this before touching anything below.
--
-- The `OAT` (own-account transfer) file moves what the platform KEEPS out of the account that
-- receives customer money and into the company revenue account. That is: the commission deducted
-- from the guard's pay, the cancellation fee retained when a customer backs out, the tip the
-- customer is billed, and the share of a multi-guard booking that is billed but never paid out.
--
-- It must NOT sweep two things that are sitting in the same account and are NOT ours:
--   * VAT (7%) — collected FOR the Revenue Department. It is a LIABILITY the moment we take it, not
--     income; the repo already encodes exactly this (`NET_REVENUE_EXPR` subtracts `vat_amount`, with
--     the reasoning inline). It is remitted MONTHLY via ภ.พ.30 e-filing, not by a bulk transfer file.
--   * The WHT withheld from guards (`payout_batch_items.wht`) — likewise the Revenue Department's
--     money, remitted via ภ.ง.ด.3/53 e-filing by the 7th of the following month.
-- Sweeping either into the revenue account would move the Revenue Department's money into company
-- income, and the shortfall would surface as a tax liability with no cash behind it. VAT and WHT get
-- REPORTS that back a filing (`/admin/reports/vat-register`, `/admin/reports/wht-payees`), never a
-- transfer file. Do not "simplify" the sweep by folding them in.
--
-- ONE FILE PER STREAM. A `BCHDET` carries exactly one product code, so this is its own upload —
-- never merged with the guard payout (③ `PPY`) or the customer refunds (① `PPY`). Its product is
-- `OAT`, and structurally it is the odd one out: an `OAT` batch credits ONE destination (the
-- company's own SCB account), so the file has a SINGLE `TXNDET` line summing the whole sweep. The
-- per-booking rows in `deduction_batch_items` are the LEDGER behind that one credit line, not
-- separate recipients — which is why `recipient_count` on a deduction batch is always 1 and the
-- item count is the interesting number.
--
-- Per-service schema ownership: ONLY payment writes schema `payment`. NO cross-service FKs —
-- `booking_id`/`created_by`/`voided_by` are bare UUIDs owned by booking/identity.
-- All money columns are NUMERIC (never float) — exact decimal, `rust_decimal::Decimal` end-to-end.
--
-- IDEMPOTENT (CLAUDE.md): ADD COLUMN IF NOT EXISTS / CREATE … IF NOT EXISTS + duplicate_object
-- catches throughout, so applying it twice is a no-op, and it is safe WITHOUT --single-transaction.

-- ── (a) the pricing SNAPSHOT — the numbers the cut is computed from ──────────────────────────
--
-- THE DEFECT THIS FIXES. The single largest component of the cut cannot be read from the database
-- today. `payments.commission_percent` (migration 0005) stores the RATE but never the commission
-- AMOUNT in baht, and `base_fee` / the booked `hours` / `guard_count` / `tip` live in BOOKING's
-- schema, not payment's. So every figure in a platform-cut report would need a cross-service HTTP
-- fan-out — and, worse, a HISTORICAL export could never be reproduced, because booking's row may
-- have changed since the job was settled. A money report that returns a different answer next month
-- for the same closed month is not a report.
--
-- ALL FIVE ARE NULLABLE, and a NULL means "this row predates the snapshot", NOT "zero" — the same
-- convention migration 0005 states in its header for `subtotal`/`vat_amount`/`commission_percent`,
-- and it matters more here: reading a NULL `commission_amount` as 0 would silently UNDER-REPORT the
-- platform's cut, which is the one direction a money report must never be wrong in. The reports
-- therefore EXCLUDE an incomplete row and report the excluded COUNT with a reason, rather than
-- summing it as zero.
--
-- NO BACKFILL IS ATTEMPTED, deliberately, and the reason is not laziness:
--   * the four multiplicands are not recoverable from what payment stores — `subtotal =
--     base_fee × hours × guard_count + tip` is ONE equation in FOUR unknowns, so no SQL can invert it;
--   * the only other source is booking's `GET /internal/bookings/{id}`, which returns the booking's
--     CURRENT columns. A migration cannot make HTTP calls at all, and a backfill job that could would
--     be writing today's booking values onto a job settled months ago — inventing exactly the
--     "historical export cannot be reproduced" defect this snapshot exists to remove;
--   * an honest "N jobs unknown, here is why" beats a number that looks complete and is not.
-- Pre-snapshot rows therefore stay NULL forever and are visible as an exclusion count in the
-- deduction preview. Every settle path that writes the VAT split writes these in the same statement,
-- so from this migration forward the two can never drift apart.
ALTER TABLE payment.payments
    -- ฿ per hour per guard, snapshotted from the booking at charge time (VAT-EXCLUSIVE).
    ADD COLUMN IF NOT EXISTS base_fee          NUMERIC(12,2),
    -- The duration the customer booked and was billed for (the proration denominator).
    ADD COLUMN IF NOT EXISTS booked_hours      INT,
    -- How many guards the customer was BILLED for. Only one is ever paid (see the technical-debt
    -- note under `deduction_batch_items.unpaid_guard_share`).
    ADD COLUMN IF NOT EXISTS guard_count       INT,
    -- The flat gratuity billed to the customer. Never prorated, and — today — never paid to the
    -- guard (the other half of the same technical debt).
    ADD COLUMN IF NOT EXISTS tip               NUMERIC(12,2),
    -- THE COMMISSION IN BAHT: round(round(base_fee × hours_worked, 2) × commission_percent / 100, 2),
    -- computed by the SAME pure function the payout deducts with
    -- (`domain::settlement::commission_on` ∘ `guard_gross`), so the money the guard is not paid and
    -- the money the platform sweeps are provably the same number. Written from the BOOKED hours at
    -- pre-pay (an estimate) and rewritten from the ACTUAL worked hours at the completion reconcile;
    -- a cancelled job carries 0, because no guard was paid and so no commission was deducted.
    ADD COLUMN IF NOT EXISTS commission_amount NUMERIC(12,2);

-- Sanity CHECKs, NULL-tolerant exactly like migration 0005's. Money never goes negative, an hour
-- count never does, and a booking is for at least one guard when it is known at all.
DO $$ BEGIN
    ALTER TABLE payment.payments
        ADD CONSTRAINT chk_payments_base_fee_non_negative
            CHECK (base_fee IS NULL OR base_fee >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE payment.payments
        ADD CONSTRAINT chk_payments_booked_hours_non_negative
            CHECK (booked_hours IS NULL OR booked_hours >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE payment.payments
        ADD CONSTRAINT chk_payments_guard_count_positive
            CHECK (guard_count IS NULL OR guard_count >= 1);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE payment.payments
        ADD CONSTRAINT chk_payments_tip_non_negative
            CHECK (tip IS NULL OR tip >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE payment.payments
        ADD CONSTRAINT chk_payments_commission_amount_non_negative
            CHECK (commission_amount IS NULL OR commission_amount >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN payment.payments.base_fee IS
    'Snapshot of the booking''s ฿/hour/guard at charge time (VAT-exclusive). NULL = the row predates the snapshot (migration 0013) — NOT zero; the platform-cut reports EXCLUDE such rows and count them.';
COMMENT ON COLUMN payment.payments.booked_hours IS
    'Snapshot of the booked duration the customer was billed for. NULL = predates the snapshot, not zero.';
COMMENT ON COLUMN payment.payments.guard_count IS
    'Snapshot of how many guards the customer was BILLED for. Only one is ever paid today (known, deferred bug) — the difference is swept as platform cut. NULL = predates the snapshot, not zero.';
COMMENT ON COLUMN payment.payments.tip IS
    'Snapshot of the flat gratuity billed to the customer. Never prorated and — today — never paid to the guard (known, deferred bug), so it is part of the platform cut. NULL = predates the snapshot, not zero.';
COMMENT ON COLUMN payment.payments.commission_amount IS
    'The commission in BAHT deducted from the guard''s pay: round(round(base_fee × hours_worked,2) × commission_percent/100, 2) — the same pure function the payout deducts with. Estimate at pre-pay (booked hours), rewritten at the completion reconcile (actual hours), 0 on a cancellation (no guard was paid). NULL = predates the snapshot, not zero.';

-- ── (b) WHERE the sweep lands — the company revenue account ──────────────────────────────────
--
-- It goes on `payout_config` rather than a sibling singleton table. That table is misnamed by
-- history — it is already the COMPANY BANKING settings row, not the payout's: stream ① (refunds)
-- reads its `debit_account` / `fee_debit_account` / `fee_charge_code` / `max_transfer_per_txn`
-- through `build_transfer_config`, and stream ② needs the same four. A second singleton would mean
-- two rows to configure, two upserts to keep in step, and a settings screen reading the same
-- company's bank details from two places — for one extra column. (Renaming the table is a separate,
-- larger change: the column list is a published API shape.)
--
-- It is validated as a REAL SCB account (10 digits + the §14 check digit) at SAVE time and AGAIN at
-- EXPORT time, exactly like the two debit accounts — because an `OAT` credit line may only address
-- an SCB account (doc §7.4, `TBBankPAY` holds only `014`), and a check-digit typo is BATCH-fatal:
-- SCB rejects the file after `deduction_batch_items` has already marked those jobs swept.
ALTER TABLE payment.payout_config
    ADD COLUMN IF NOT EXISTS revenue_account TEXT;

COMMENT ON COLUMN payment.payout_config.revenue_account IS
    'The company SCB account the PLATFORM-CUT sweep (stream ②, product OAT) is CREDITED to — 10 digits passing the §14 check digit, validated at save time and again at export. NULL until an admin sets it; the sweep export refuses to run without it.';

-- ── (c) deduction_batches — one row per generated SCB `OAT` sweep file ───────────────────────
-- The FULL P2 lifecycle from day one, shaped like `refund_batches` (which was itself shaped like
-- `payout_batches` AFTER migration 0009). Stream ③ learned the hard way that an export which streams
-- the file exactly once and stores nothing is a ONE-WAY DOOR: a failed download, a closed tab, a
-- proxy timeout or an SCB rejection left the work marked settled forever with no copy of the file
-- meant to settle it, and a hand-written UPDATE in production as the only remedy.
CREATE TABLE IF NOT EXISTS payment.deduction_batches (
    id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    file_ref         TEXT          NOT NULL,          -- HEADER field 1 = batch_ref || 'OAT'
    system_ref       TEXT          NOT NULL,          -- HEADER field 2 (PGUARD-DEDUCT)
    batch_ref        TEXT          NOT NULL,          -- BCHDET field 1 — the bare 12-digit DDMMYYHHMMSS stamp
    value_date       DATE          NOT NULL,          -- effective/value date (a Bangkok business day)
    -- Σ of every item's cut = the ONE TXNDET credit amount. An OAT batch has a single destination,
    -- so this is both the batch total and that line's amount.
    total_amount     NUMERIC(12,2) NOT NULL,
    -- The company account this file credited, SNAPSHOTTED. `payout_config.revenue_account` can be
    -- edited later; a generated money file must still say where its money actually went.
    credit_account   TEXT          NOT NULL,
    -- How many CREDIT LINES the file carries. Always 1 for an OAT sweep (one destination), kept for
    -- shape-compatibility with the other two streams' history screens rather than as a live figure —
    -- the number an operator cares about here is the ITEM count.
    recipient_count  INT           NOT NULL DEFAULT 1,
    -- How many JOBS' cuts this sweep collected (= live deduction_batch_items at export time).
    job_count        INT           NOT NULL,
    status           TEXT          NOT NULL DEFAULT 'generated',
    status_note      TEXT,                            -- free text kept with the latest status change
    void_reason      TEXT,                            -- why the whole file was cancelled (mandatory at the API)
    file_text        TEXT,                            -- the EXACT bytes handed to the admin (re-download)
    created_by       UUID,                            -- acting admin (bare UUID, no FK)
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    uploaded_at      TIMESTAMPTZ,
    confirmed_at     TIMESTAMPTZ,
    rejected_at      TIMESTAMPTZ,
    voided_at        TIMESTAMPTZ,
    voided_by        UUID                             -- acting admin (bare UUID, no FK)
);

-- The status vocabulary is closed and identical to the other two streams': the pure transition table
-- in `services/payment/src/domain/batch_status.rs` is the only writer, and this CHECK is the last
-- line if anything ever writes the column by hand.
DO $$ BEGIN
    ALTER TABLE payment.deduction_batches
        ADD CONSTRAINT chk_deduction_batches_status
            CHECK (status IN ('generated', 'uploaded', 'confirmed', 'rejected', 'voided'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ONE file ref, ONE file — the same guard migration 0010 retro-fitted onto the payout and 0011
-- shipped for refunds. `batch_ref` is a timestamp at ONE-SECOND resolution and `file_ref` is that
-- stamp plus the product code, so two sweeps committed in the same Bangkok second would otherwise
-- both succeed (with DISJOINT job selections, which the per-payment marker has nothing to catch) and
-- put out two files sharing the customer transaction ref the bank de-dups on. The CROSS-stream case
-- is caught by `payment.scb_file_refs` (migration 0012), whose CHECK already admits `'deduction'`.
-- NOT `CONCURRENTLY`: the table is empty at creation and is written only by an admin export, so the
-- brief lock is free, while a failed CONCURRENTLY build would leave an INVALID index that a
-- re-apply's `IF NOT EXISTS` silently skips — the de-dup guard permanently off on a money table.
CREATE UNIQUE INDEX IF NOT EXISTS uq_deduction_batches_file_ref
    ON payment.deduction_batches (file_ref);

-- ── (d) deduction_batch_items — one row per JOB whose cut was swept ──────────────────────────
-- The LEDGER behind the file's single credit line, and the paid-marker that makes a double-sweep
-- impossible. Keyed on the PAYMENT row (`payment_id`), which is the row the cut was computed from —
-- not on `booking_id`, so it stays correct even if a booking ever carried two payment rows.
--
-- The components are stored SEPARATELY rather than only as a total, because the reports have to
-- answer "how much of the cut is commission vs a retained cancellation fee vs a tip vs an unpaid
-- guard share" AFTER the fact, and re-deriving them from the payments row would give a different
-- answer once the two technical debts below are fixed.
CREATE TABLE IF NOT EXISTS payment.deduction_batch_items (
    id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id            UUID          NOT NULL REFERENCES payment.deduction_batches(id) ON DELETE CASCADE,
    payment_id          UUID          NOT NULL,          -- the payment row swept (same schema, no FK needed for the marker semantics; see the index below)
    booking_id          UUID          NOT NULL,          -- what the cut is FOR (bare UUID, owned by booking)
    -- The five components of THIS job's cut. They sum to `amount`, exactly (a DB CHECK below).
    commission          NUMERIC(12,2) NOT NULL,          -- deducted from the guard's pay
    cancellation_fee    NUMERIC(12,2) NOT NULL,          -- VAT-EXCLUSIVE part of a retained cancellation fee
    tip                 NUMERIC(12,2) NOT NULL,          -- billed to the customer, not paid to the guard (deferred bug)
    unpaid_guard_share  NUMERIC(12,2) NOT NULL,          -- billed for N guards, one paid (deferred bug)
    -- The only component that may be NEGATIVE — see the CHECK below for why it has to exist.
    rounding_adjustment NUMERIC(12,2) NOT NULL DEFAULT 0,
    amount              NUMERIC(12,2) NOT NULL,          -- the job's total cut = Σ of the five above
    voided_at           TIMESTAMPTZ,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- The four NAMED components are money the platform genuinely kept, and none of them can be negative.
-- `rounding_adjustment` and `amount` are deliberately UNCONSTRAINED in sign:
--
--   the settled bill prorates the base with the UNROUNDED worked-hours ratio
--   (`round(base × hours × guards × actual/booked, 2)`) while the guard is paid off `actual_hours`
--   ROUNDED to 2 dp (`NUMERIC(6,2)`, what the payout reads) — so on a job of 1.995 worked hours at
--   ฿500/h the customer is billed 997.50 and the guard's gross is 1000.00, and the platform is ฿2.50
--   OUT OF POCKET on that job. Forcing that to zero would silently invent ฿2.50 of income; refusing
--   the job would strand it in the backlog forever for a rounding artefact. It is recorded for what
--   it is, and a job with a negative TOTAL simply nets off against the rest of the sweep. The FILE
--   total is what must be positive, and SCB's own ฿0.01 minimum enforces that at the credit line.
DO $$ BEGIN
    ALTER TABLE payment.deduction_batch_items
        ADD CONSTRAINT chk_deduction_items_components_non_negative
            CHECK (commission >= 0 AND cancellation_fee >= 0 AND tip >= 0
                   AND unpaid_guard_share >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- THE COMPONENTS MUST SUM TO THE TOTAL, enforced by the database rather than by every future writer
-- remembering. This is the row an accountant reads when asked to justify a transfer into company
-- income; a total that does not equal its own breakdown is unanswerable.
DO $$ BEGIN
    ALTER TABLE payment.deduction_batch_items
        ADD CONSTRAINT chk_deduction_items_amount_is_the_sum
            CHECK (amount = commission + cancellation_fee + tip + unpaid_guard_share
                            + rounding_adjustment);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- THE SWEPT-MARKER: one LIVE item per payment row, ever. PARTIAL on `voided_at IS NULL` for the same
-- reason as the other two streams: voiding exists to put the job BACK in the sweepable backlog, the
-- item row is kept as history rather than deleted, and Postgres cannot express "unique unless the
-- PARENT row is voided" in a partial index (an index predicate sees one table). So the void is
-- stamped on the ITEM and the unique is partial on it. A full unique here would leave a voided job
-- permanently un-sweepable — the precise bug void exists to fix.
CREATE UNIQUE INDEX IF NOT EXISTS uq_deduction_batch_items_payment_live
    ON payment.deduction_batch_items (payment_id)
 WHERE voided_at IS NULL;

-- The batch drill-down.
CREATE INDEX IF NOT EXISTS idx_deduction_batch_items_batch
    ON payment.deduction_batch_items (batch_id);

COMMENT ON TABLE  payment.deduction_batches IS
    'One row per generated SCB Business Net PLATFORM-CUT sweep file (stream ② ยอดที่โดนหักเข้าระบบ — product OAT, own-account transfer into the company revenue account). Carries the platform''s cut ONLY: never VAT and never the WHT withheld from guards, both of which are the Revenue Department''s money and are remitted by e-filing (ภ.พ.30 / ภ.ง.ด.3/53), not by a transfer file.';
COMMENT ON TABLE  payment.deduction_batch_items IS
    'One row per JOB whose platform cut was swept — the LEDGER behind the file''s SINGLE credit line, not a list of recipients (an OAT batch has one destination). payment_id is the swept-marker: the partial unique on the LIVE rows makes a double-sweep impossible while letting a void return the job to the sweepable backlog.';
COMMENT ON COLUMN payment.deduction_batches.credit_account IS
    'The company SCB account this file credited, snapshotted at export. payout_config.revenue_account may be edited later; a generated money file must still say where its money went.';
COMMENT ON COLUMN payment.deduction_batches.recipient_count IS
    'Always 1 — an OAT batch credits ONE destination, so the file carries a single TXNDET summing the whole sweep. Kept for shape-compatibility with the payout/refund history screens; job_count is the number that means something here.';
COMMENT ON COLUMN payment.deduction_batches.job_count IS
    'How many jobs'' cuts this sweep collected (= the item rows). The per-booking rows back the one credit line.';
COMMENT ON COLUMN payment.deduction_batches.status IS
    'Lifecycle: generated → uploaded → confirmed | rejected; generated/uploaded/rejected → voided. confirmed + voided are TERMINAL. The transition table lives in domain/batch_status.rs.';
COMMENT ON COLUMN payment.deduction_batch_items.tip IS
    'The tip billed to the customer. It is in the platform cut ONLY because of a KNOWN, DEFERRED bug: the customer is charged a gratuity the guard never receives. When that is fixed this component becomes 0 and the guard''s payout grows by the same amount.';
COMMENT ON COLUMN payment.deduction_batch_items.unpaid_guard_share IS
    'The billed-but-unpaid share of a multi-guard booking. In the platform cut ONLY because of a KNOWN, DEFERRED bug: a booking can be billed for N guards while booking.bookings carries a single guard_id, so exactly one guard is ever paid. When that is fixed this component becomes 0.';
COMMENT ON COLUMN payment.deduction_batch_items.cancellation_fee IS
    'The VAT-EXCLUSIVE part of a retained cancellation fee. The fee is retained out of VAT-INCLUSIVE money, so the VAT inside it belongs to the Revenue Department and is deliberately NOT swept.';
COMMENT ON COLUMN payment.deduction_batch_items.rounding_adjustment IS
    'What is left of the settled bill after the guard''s gross, the tip and the unpaid guard shares are taken out: the drift between prorating on the UNROUNDED worked-hours ratio (the customer''s bill) and paying on actual_hours ROUNDED to 2 dp (the guard''s gross). A few satang, and the ONLY component that may be negative — the platform really can be marginally out of pocket on one job. Clamping it would invent income; the job simply nets off against the rest of the sweep.';
COMMENT ON COLUMN payment.deduction_batch_items.voided_at IS
    'Set on EVERY item when its batch is voided, and on the named ones by a per-item void. Denormalised deliberately: the swept-marker unique is PARTIAL on this column (Postgres cannot make a unique depend on the parent row), so voiding returns the job to the sweepable backlog while keeping the history.';
