-- pguard payment-service — VAT 7%, the per-service commission split, and the cancellation fee.
--
-- THE MONEY PATH. Three changes land on payment.payments, all NULLABLE because pre-migration rows
-- were charged under the old (VAT-free, fee-free) rules and must keep their historical figures —
-- a NULL here means "this charge predates the rule", NOT "zero was computed". Every read path
-- COALESCEs accordingly.
--
-- (1) THE VAT SPLIT — `subtotal` + `vat_amount`.
--     Catalog prices are VAT-EXCLUSIVE; 7% VAT is ADDED on top, so the customer now pays MORE than
--     before for the same job (decision taken 2026-08-10). The charged `amount` (and
--     `expected_total`) therefore become the GRAND TOTAL, and these two columns record the split
--     that produced it:
--         subtotal    = base_fee × hours × guard_count + tip   (VAT-exclusive, unchanged rule)
--         vat_amount  = round(subtotal × 0.07, 2)
--         amount      = subtotal + vat_amount                  ← what the customer transfers
--     INVARIANT maintained by EVERY write path (pre-pay, slip, reconcile, cancellation):
--         subtotal + vat_amount = COALESCE(final_amount, amount)
--     i.e. the split always describes the CURRENTLY SETTLED bill, not a stale estimate. The
--     completion reconcile prorates the SUBTOTAL and recomputes VAT from the prorated subtotal
--     (never prorating VAT independently — the two would drift by rounding), and rewrites both
--     columns. This is also what a Thai tax invoice (ใบกำกับภาษี) must print.
--
-- (2) THE CANCELLATION FEE — `cancellation_fee` (snapshot) + `cancellation_fee_charged` (actual).
--     `cancellation_fee` is SNAPSHOTTED from the booking at charge time (booking snapshots it from
--     the catalog at creation), so editing the catalog later never rewrites the terms of a job that
--     is already paid for, and the refund path needs no cross-service read. When the CUSTOMER
--     cancels we keep `cancellation_fee_charged = min(cancellation_fee, amount_paid)` — "take what
--     is there, never leave a debt" — and refund the rest. When the GUARD withdraws (declined) the
--     customer did nothing wrong: no fee, full refund, and `cancellation_fee_charged` is 0.
--
-- (3) THE COMMISSION — `commission_percent`.
--     Commission is PER SERVICE and is deducted from the GUARD's pay (the customer pays the same
--     either way). It is likewise SNAPSHOTTED from the booking at charge time so the guard's
--     earnings ledger (`GET /payments/earnings`) can show what was deducted from a job priced
--     months ago, without payment ever reading booking's schema (per-service ownership: only
--     payment writes schema `payment`, and it reads booking over the service-JWT'd internal API).
--
-- All money columns are NUMERIC (never float) — exact decimal, `rust_decimal::Decimal` end-to-end.
-- Dev note: payment.payments is small/empty here (no production users), so ADD COLUMN is instant.

ALTER TABLE payment.payments
    -- (1) the VAT split behind `amount` / `final_amount`.
    ADD COLUMN subtotal                 NUMERIC(12,2),  -- VAT-exclusive base+tip of the settled bill
    ADD COLUMN vat_amount               NUMERIC(12,2),  -- 7% VAT charged on that subtotal
    -- (2) the cancellation fee: the booking's snapshot, and what was actually retained.
    ADD COLUMN cancellation_fee         NUMERIC(12,2),  -- snapshot of booking.cancellation_fee
    ADD COLUMN cancellation_fee_charged NUMERIC(12,2),  -- min(cancellation_fee, amount_paid), or 0
    -- (3) the commission deducted from the guard's pay for this job.
    ADD COLUMN commission_percent       NUMERIC(5,2);   -- snapshot of booking.commission_percent

-- Sanity CHECKs (NULL-tolerant — pre-migration rows carry none). Money never goes negative and a
-- commission is a percentage; the booking side has the same guards, but payment must not depend on
-- another service's constraints for its own integrity.
ALTER TABLE payment.payments
    ADD CONSTRAINT chk_payments_subtotal_non_negative
        CHECK (subtotal IS NULL OR subtotal >= 0),
    ADD CONSTRAINT chk_payments_vat_non_negative
        CHECK (vat_amount IS NULL OR vat_amount >= 0),
    ADD CONSTRAINT chk_payments_cancellation_fee_non_negative
        CHECK (cancellation_fee IS NULL OR cancellation_fee >= 0),
    ADD CONSTRAINT chk_payments_cancellation_fee_charged_non_negative
        CHECK (cancellation_fee_charged IS NULL OR cancellation_fee_charged >= 0),
    ADD CONSTRAINT chk_payments_commission_percent_range
        CHECK (commission_percent IS NULL OR (commission_percent >= 0 AND commission_percent <= 100));

COMMENT ON COLUMN payment.payments.subtotal IS
    'VAT-EXCLUSIVE base+tip of the currently settled bill. NULL = charged before VAT was introduced. Invariant: subtotal + vat_amount = COALESCE(final_amount, amount).';
COMMENT ON COLUMN payment.payments.vat_amount IS
    'VAT (7%) charged on `subtotal`. Collected FOR the Revenue Department — excluded from platform net revenue.';
COMMENT ON COLUMN payment.payments.cancellation_fee IS
    'Snapshot of the booking''s cancellation fee at charge time (NULL/0 = none). What a CUSTOMER cancellation would cost.';
COMMENT ON COLUMN payment.payments.cancellation_fee_charged IS
    'Fee actually retained on cancellation: min(cancellation_fee, amount paid) when the CUSTOMER cancelled, else 0. NULL = the booking was never cancelled.';
COMMENT ON COLUMN payment.payments.commission_percent IS
    'Snapshot of the booking''s per-service commission % at charge time. Deducted from the GUARD''s pay, never added to the customer''s bill.';
