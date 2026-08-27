-- pguard payment-service — SLIP OVERPAY ledgering + the SECOND-transfer (double-pay) record.
--
-- THE MONEY PATH. Two money-leak fixes from the 2026-08 deep review land here, both about a slip
-- payment that put MORE money into our account than the system tracked:
--
-- (1) OVERPAY (`payment.payments.overpaid_amount`).
--     The slip re-validation accepts `slip_amount >= estimate` (overpay allowed). Until now the
--     payment row recorded only the ESTIMATE (`amount`), so the excess `slip_amount − estimate`
--     was kept but ledgered NOWHERE — every refund (cancel, race-compensator, completion reconcile)
--     computed off `amount` and therefore UNDER-refunded the customer by the overpay. We now persist
--     the excess here so every refund path returns what the customer ACTUALLY transferred
--     (`amount + overpaid_amount`), never just the estimate. NOT NULL DEFAULT 0 — a simulated
--     pre-pay and any exact payment carry 0, so existing rows and every non-slip charge are unaffected.
--     INVARIANT unchanged: `subtotal + vat_amount = COALESCE(final_amount, amount)` still describes
--     the SETTLED bill; the overpay is a separate always-refundable rider on top of it, never revenue.
--
-- (2) SECOND / DUPLICATE TRANSFER (`payment.payment_slips.applied` + `.refund_status`).
--     A customer can double-transfer (bank-app timeout → two REAL transfers, distinct transRefs,
--     each ≥ the estimate) for ONE booking. The first settles it; the second used to hit the
--     "already paid" branch and return 200 with the second slip recorded NOWHERE — a real transfer
--     that vanished from the system (no row, no image reference, invisible to support). We now record
--     that second, DIFFERENT slip as an UNAPPLIED row in the SAME `payment_slips` table
--     (`applied = FALSE`, `refund_status = 'pending'`), so:
--       * the UNIQUE(trans_ref)/(reference_id) indexes ALSO reserve the extra transfer's refs — it
--         can never later be reused to pay a DIFFERENT booking (closes the reuse side-channel);
--       * the money is durably tracked and refundable instead of silently lost.
--     `applied = TRUE` = the slip that actually settled its payment (the historical meaning; the
--     DEFAULT keeps every existing + first-pay row correct with no backfill).

-- (1) the overpay rider.
ALTER TABLE payment.payments
    ADD COLUMN overpaid_amount NUMERIC(12,2) NOT NULL DEFAULT 0;

ALTER TABLE payment.payments
    ADD CONSTRAINT chk_payments_overpaid_non_negative
        CHECK (overpaid_amount >= 0);

COMMENT ON COLUMN payment.payments.overpaid_amount IS
    'Excess the customer transferred ABOVE the estimate on a slip payment (max(0, slip_amount − amount)); 0 for simulated/exact payments. Always refundable on top of the settled bill — never platform revenue. Every refund path returns amount + overpaid_amount.';

-- (2) mark applied vs. unapplied (extra) slips, and drive the extra transfer's own refund workflow.
ALTER TABLE payment.payment_slips
    ADD COLUMN applied       BOOLEAN NOT NULL DEFAULT TRUE,  -- FALSE = a recorded-but-unapplied extra transfer (double-pay)
    ADD COLUMN refund_status TEXT;                            -- NULL normally; 'pending'|'processed' for an unapplied extra transfer

ALTER TABLE payment.payment_slips
    ADD CONSTRAINT chk_payment_slips_refund_status
        CHECK (refund_status IS NULL OR refund_status IN ('pending', 'processed'));

-- Find the extra (unapplied) transfers awaiting refund — the admin "double-paid, refund me" signal.
-- Partial index on the (rare) unapplied rows keeps it cheap as payment_slips grows.
CREATE INDEX idx_payment_slips_unapplied_refunds
    ON payment.payment_slips (refund_status, created_at DESC)
    WHERE applied = FALSE AND refund_status IS NOT NULL;

COMMENT ON COLUMN payment.payment_slips.applied IS
    'TRUE (default) = the verified slip that SETTLED its payment (1:1, the historical meaning). FALSE = a SECOND, different verified transfer for an already-paid booking (a double-pay) — recorded so the money is tracked + refundable and its transRef/referenceId are reserved against reuse, but it settled nothing.';
COMMENT ON COLUMN payment.payment_slips.refund_status IS
    'Refund workflow for an UNAPPLIED extra transfer (applied = FALSE): ''pending'' once recorded, ''processed'' once refunded. Always NULL on an applied slip (the payment row carries the applied charge''s refund state).';
