-- pguard payment-service — STREAM ① ยอดที่ต้องโอนคืนกับคนจ้าง: the CUSTOMER-REFUND SCB file.
--
-- THE DEFECT THIS FIXES. Money owed back to a customer is computed, written as
-- `refund_status = 'pending'`, announced to them by push — and then never leaves the building.
-- NOTHING in the codebase has ever written `refund_status = 'processed'`: the queue behind
-- `GET /admin/refunds/queue` only ever GAINS rows, and its handler's note that "v2 refunds are
-- event-driven" is aspirational, not true. These two tables are what lets an admin actually pay
-- that queue down, over the same SCB Business Net rail that pays the guards (stream ③).
--
-- ONE FILE PER STREAM. A `BCHDET` carries exactly one product code, so the refund file is its own
-- upload — never merged with the payout. It is a PromptPay (`PPY`) credit addressed by the phone
-- REGISTRATION already captured (the 10-digit `MOB` proxy), and `wht = 0` on every line: a refund is
-- the customer's own money coming back, not assessable income, so no `WHTCER`/`WHTDET` certificate
-- is emitted and no company TIN is needed to send one.
--
-- TWO LANES OWE THE MONEY, which is why the paid-marker below is a COMPOSITE key rather than a
-- single id (see `payment.refund_batch_items`):
--   A. `payment.payments`      — `refund_status = 'pending'` with `refund_amount > 0`. Covers the
--      completion-reconcile overpay, the cancellation refund (full or net of a retained fee) and the
--      race-lost pre-pay compensator.
--   B. `payment.payment_slips` — `applied = FALSE AND refund_status = 'pending'`: a SECOND, REAL
--      transfer for an already-paid booking (migration 0006). A different table, a different id and
--      a different amount column — and no `customer_id` of its own, so it is resolved through its
--      `payment_id`.
--
-- Per-service schema ownership: ONLY payment writes schema `payment`. NO cross-service FKs —
-- `customer_id`/`booking_id`/`created_by`/`voided_by` are bare UUIDs owned by identity/booking.
-- All money columns are NUMERIC (never float) — exact decimal, `rust_decimal::Decimal` end-to-end.
--
-- IDEMPOTENT (CLAUDE.md): CREATE … IF NOT EXISTS + duplicate_object catches throughout, so applying
-- it twice is a no-op, and it is safe WITHOUT --single-transaction.

-- ── (a) refund_batches — one row per generated SCB refund file ───────────────────────────────
-- Shaped like `payout_batches` AFTER migration 0009, deliberately: the whole lifecycle ships on day
-- one instead of being retro-fitted. Stream ③ learned the hard way that an export which streams the
-- file exactly once and stores nothing is a ONE-WAY DOOR — a failed download, a closed tab, a proxy
-- timeout or an SCB rejection left the obligations marked settled forever with no copy of the file
-- meant to settle them, and a hand-written UPDATE in production as the only remedy.
CREATE TABLE IF NOT EXISTS payment.refund_batches (
    id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    file_ref         TEXT          NOT NULL,          -- HEADER field 1 = batch_ref || product code
    system_ref       TEXT          NOT NULL,          -- HEADER field 2 (PGUARD-REFUND)
    batch_ref        TEXT          NOT NULL,          -- BCHDET field 1 — the bare 12-digit DDMMYYHHMMSS stamp
    value_date       DATE          NOT NULL,          -- effective/value date (a Bangkok business day)
    total_amount     NUMERIC(12,2) NOT NULL,          -- Σ transfers the file debits
    recipient_count  INT           NOT NULL,          -- how many CUSTOMERS (= TXNDET lines), not obligations
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

-- The status vocabulary is closed and identical to the payout's: the pure transition table in
-- `services/payment/src/domain/batch_status.rs` is the only writer, and this CHECK is the last line
-- if anything ever writes the column by hand.
DO $$ BEGIN
    ALTER TABLE payment.refund_batches
        ADD CONSTRAINT chk_refund_batches_status
            CHECK (status IN ('generated', 'uploaded', 'confirmed', 'rejected', 'voided'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ONE file ref, ONE file. `batch_ref` is a timestamp at ONE-SECOND resolution and `file_ref` is that
-- stamp plus the product code, so two refund exports committed in the same Bangkok second would
-- otherwise both succeed — even with DISJOINT customer selections, which the per-obligation
-- paid-marker has nothing to catch — and put out two files sharing the customer transaction refs the
-- bank de-dups on. This is the exact defect migration 0010 fixed for the payout; it ships here from
-- the start. NOT `CONCURRENTLY`: the table is empty at creation and is written only by an admin
-- export, so the brief lock is free, while a failed CONCURRENTLY build would leave an INVALID index
-- that a re-apply's `IF NOT EXISTS` silently skips — the de-dup guard permanently off on a money table.
CREATE UNIQUE INDEX IF NOT EXISTS uq_refund_batches_file_ref
    ON payment.refund_batches (file_ref);

-- ── (b) refund_batch_items — one row per REFUND OBLIGATION paid ──────────────────────────────
-- The paid-marker, and the part that has to be RIGHT. Because two different tables owe the money,
-- the marker is a COMPOSITE: (`source_kind`, `source_id`) names the obligation — a `payment.payments`
-- row or a `payment.payment_slips` row — so lane A and lane B can never collide on a shared id space
-- and neither can be exported twice.
CREATE TABLE IF NOT EXISTS payment.refund_batch_items (
    id           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id     UUID          NOT NULL REFERENCES payment.refund_batches(id) ON DELETE CASCADE,
    -- WHICH table owes this money. 'payment' = payment.payments.refund_amount (reconcile overpay /
    -- cancellation / race compensator); 'slip' = payment.payment_slips.amount (a genuine double-pay).
    source_kind  TEXT          NOT NULL,
    source_id    UUID          NOT NULL,          -- the payments.id / payment_slips.id (same schema, no FK: the row may be either)
    booking_id   UUID          NOT NULL,          -- what the refund is FOR (bare UUID, owned by booking)
    customer_id  UUID          NOT NULL,          -- who is refunded (bare UUID, owned by identity)
    amount       NUMERIC(12,2) NOT NULL,          -- this ONE obligation's share of the customer's transfer
    voided_at    TIMESTAMPTZ,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now()
);

DO $$ BEGIN
    ALTER TABLE payment.refund_batch_items
        ADD CONSTRAINT chk_refund_batch_items_source_kind
            CHECK (source_kind IN ('payment', 'slip'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE payment.refund_batch_items
        ADD CONSTRAINT chk_refund_batch_items_amount_positive
            CHECK (amount > 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- THE PAID-MARKER: one LIVE item per obligation, ever. PARTIAL on `voided_at IS NULL` from the
-- start — the shape migration 0009 had to arrive at for the payout, for exactly the same reason:
-- voiding exists to put the obligation BACK in the refundable backlog, the item row is kept as
-- history rather than deleted, and Postgres cannot express "unique unless the PARENT row is voided"
-- in a partial index (an index predicate sees one table). So the void is stamped on the ITEM and the
-- unique is partial on it. A full unique here would leave a voided obligation permanently
-- unrefundable — the precise bug void exists to fix.
CREATE UNIQUE INDEX IF NOT EXISTS uq_refund_batch_items_source_live
    ON payment.refund_batch_items (source_kind, source_id)
 WHERE voided_at IS NULL;

-- The two ways the items are read: the batch drill-down, and "everything ever refunded to THIS
-- customer".
CREATE INDEX IF NOT EXISTS idx_refund_batch_items_batch
    ON payment.refund_batch_items (batch_id);
CREATE INDEX IF NOT EXISTS idx_refund_batch_items_customer
    ON payment.refund_batch_items (customer_id, created_at DESC);

-- Lane B's backlog scan: the unapplied, still-pending extra transfers. `idx_payment_slips_unapplied_refunds`
-- (migration 0006) already covers `(refund_status, created_at DESC) WHERE applied = FALSE AND
-- refund_status IS NOT NULL`, so lane B needs no new index; lane A rides
-- `idx_payments_refund_queue` (migration 0003). Documented here so a future reader does not add a
-- third one on the same predicate.

COMMENT ON TABLE  payment.refund_batches IS
    'One row per generated SCB Business Net CUSTOMER-REFUND file (stream ① ยอดที่ต้องโอนคืนกับคนจ้าง — PromptPay MOB, wht = 0 so no ภ.ง.ด. certificate). total_amount = Σ transfers the file debits.';
COMMENT ON TABLE  payment.refund_batch_items IS
    'One row per REFUND OBLIGATION paid. (source_kind, source_id) is the paid-marker: ''payment'' = payment.payments (reconcile overpay / cancellation / race compensator), ''slip'' = payment.payment_slips (a genuine double-pay). The partial unique on the LIVE rows is what makes a double-refund impossible while letting a void return the obligation to the queue.';
COMMENT ON COLUMN payment.refund_batches.batch_ref IS
    'BCHDET field 1 — the customer BATCH ref: the bare 12-digit DDMMYYHHMMSS Bangkok stamp. Capped at 12 characters, so the product code is NOT appended here.';
COMMENT ON COLUMN payment.refund_batches.file_ref IS
    'HEADER field 1 — the customer FILE ref = batch_ref || product_code (e.g. 070926120000PPY). NOT the download filename.';
COMMENT ON COLUMN payment.refund_batches.file_text IS
    'The EXACT SCB file text handed to the admin, stored so it can be re-downloaded. Never regenerated: a regenerated file could differ (the backlog moved on) under the same batch ref.';
COMMENT ON COLUMN payment.refund_batches.status IS
    'Lifecycle: generated → uploaded → confirmed | rejected; generated/uploaded/rejected → voided. confirmed + voided are TERMINAL. The transition table lives in domain/batch_status.rs.';
COMMENT ON COLUMN payment.refund_batches.recipient_count IS
    'How many CUSTOMERS the file refunds (= TXNDET lines), NOT how many obligations — a customer with three pending refunds is one recipient on one credit line.';
COMMENT ON COLUMN payment.refund_batch_items.voided_at IS
    'Set on EVERY item when its batch is voided, and on the named ones by a per-item void. Denormalised deliberately: the paid-marker unique is PARTIAL on this column (Postgres cannot make a unique depend on the parent row), so voiding returns the obligation to the refundable backlog — and flips its source row back to refund_status = ''pending'' — while keeping the history.';
