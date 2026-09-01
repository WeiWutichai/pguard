-- pguard payment-service — GUARD PAYOUT: the SCB Business Net bulk-upload batch (PromptPay credit
-- + ภ.ง.ด.53 withholding-tax certificate) an admin generates to PAY GUARDS.
--
-- THE MONEY PATH (payout side). payment is the aggregator that OWNS money: it already knows what
-- each guard earned per completed job (base_fee × actual_hours − commission), reads the guard's
-- PII (name/tax_id/address/phone) from profile over the service-JWT'd internal API, and the company
-- WHT payer + debit config from profile.org_settings, then emits the SCB pipe-delimited file
-- (services/payment/src/domain/scb_export.rs) and RECORDS which bookings were paid so no guard is
-- ever paid twice.
--
-- Per-service schema ownership: ONLY payment writes schema `payment`. NO cross-service FKs —
-- `booking_id`/`guard_id`/`updated_by`/`created_by` are bare UUIDs owned by booking/identity.
-- All money columns are NUMERIC (never float) — exact decimal, `rust_decimal::Decimal` end-to-end.
--
-- IDEMPOTENT migration (CLAUDE.md): IF NOT EXISTS / duplicate_object catch throughout, so it can be
-- applied more than once (and WITHOUT --single-transaction).

-- (a) payout_config — the SINGLE-ROW company payout settings (debit accounts + the ภ.ง.ด. terms an
--     admin sets once). `id BOOLEAN PRIMARY KEY DEFAULT TRUE` + a CHECK pins it to at most one row
--     (the same one-row pattern profile.org_settings uses). Nullable text so an unconfigured install
--     starts blank; the export handler fails cleanly until the admin fills the debit accounts.
CREATE TABLE IF NOT EXISTS payment.payout_config (
    id                    BOOLEAN PRIMARY KEY DEFAULT TRUE,
    debit_account         TEXT,                                    -- company account transfers are DEBITED from
    fee_debit_account     TEXT,                                    -- account the transfer FEES are debited from
    wht_form_type_code    TEXT          NOT NULL DEFAULT '53',     -- ภ.ง.ด.53 (payments to a company)
    wht_pay_type_code     TEXT          NOT NULL DEFAULT '1',      -- SCB WHT pay-type code
    wht_income_type_code  TEXT          NOT NULL DEFAULT '5',      -- assessable-income type (service fee)
    wht_income_desc       TEXT          NOT NULL DEFAULT 'ค่าบริการรักษาความปลอดภัย',
    wht_rate_percent      NUMERIC(5,2)  NOT NULL DEFAULT 3,        -- standard service-fee WHT rate
    product_code          TEXT          NOT NULL DEFAULT 'PPY',    -- SCB product (PromptPay credit)
    updated_by            UUID,                                    -- acting admin (bare UUID, no FK)
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT payout_config_singleton CHECK (id = TRUE)
);

-- CHECK constraints (idempotent — skip when they already exist).
DO $$ BEGIN
    ALTER TABLE payment.payout_config
        ADD CONSTRAINT chk_payout_config_wht_rate_range
            CHECK (wht_rate_percent >= 0 AND wht_rate_percent <= 100);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Seed the single default row so GET /admin/payouts/config always has a row to read (the debit
-- accounts stay NULL until an admin sets them). ON CONFLICT keeps re-apply a no-op.
INSERT INTO payment.payout_config (id) VALUES (TRUE)
ON CONFLICT (id) DO NOTHING;

-- (b) payout_batches — one row per generated SCB file. `total_amount` is the sum of the actual
--     PromptPay transfers (net of WHT) that the file debits; `recipient_count` is how many guards
--     it pays.
CREATE TABLE IF NOT EXISTS payment.payout_batches (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_ref         TEXT          NOT NULL,          -- HEADER fileRef
    system_ref       TEXT          NOT NULL,          -- HEADER systemRef
    batch_ref        TEXT          NOT NULL,          -- BCHDET customer batch ref (<DDMMYYHHMMSS>PPY)
    value_date       DATE          NOT NULL,          -- effective/value date of the batch
    total_amount     NUMERIC(12,2) NOT NULL,          -- Σ actual transfers (income − WHT)
    recipient_count  INT           NOT NULL,
    created_by       UUID,                            -- acting admin (bare UUID, no FK)
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- (c) payout_batch_items — one row PER BOOKING PAID. `booking_id UNIQUE` is THE PAID-MARKER: a
--     booking already here is excluded from every future preview/export (booking_id NOT IN
--     payout_batch_items), and the UNIQUE constraint is the atomic last line that makes a
--     double-pay (two concurrent exports claiming the same booking) impossible. `income`/`wht`/
--     `transfer_amount` are this ONE booking's share (a guard's file recipient is the SUM of their
--     items).
CREATE TABLE IF NOT EXISTS payment.payout_batch_items (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id         UUID          NOT NULL REFERENCES payment.payout_batches(id) ON DELETE CASCADE,
    booking_id       UUID          NOT NULL,          -- the paid marker (bare UUID, owned by booking)
    guard_id         UUID          NOT NULL,          -- who was paid (bare UUID, owned by identity)
    income           NUMERIC(12,2) NOT NULL,          -- base_fee × actual_hours − commission
    wht              NUMERIC(12,2) NOT NULL,          -- round(income × wht_rate/100, 2)
    transfer_amount  NUMERIC(12,2) NOT NULL,          -- income − wht (the actual PromptPay amount)
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- THE PAID-MARKER: one payout item per booking, ever. Named UNIQUE index (idempotent via IF NOT
-- EXISTS) — a second export that tries to claim an already-paid booking hits this and aborts.
CREATE UNIQUE INDEX IF NOT EXISTS uq_payout_batch_items_booking
    ON payment.payout_batch_items (booking_id);

-- Look up all the items in a batch (the batch drill-down) + all the payouts of a guard.
CREATE INDEX IF NOT EXISTS idx_payout_batch_items_batch ON payment.payout_batch_items (batch_id);
CREATE INDEX IF NOT EXISTS idx_payout_batch_items_guard ON payment.payout_batch_items (guard_id, created_at DESC);

COMMENT ON TABLE  payment.payout_config IS
    'Single-row (id=TRUE) company payout settings: debit accounts + the ภ.ง.ด. WHT terms an admin sets once. Heads every SCB payout file.';
COMMENT ON TABLE  payment.payout_batches IS
    'One row per generated SCB Business Net payout file (PromptPay credit + ภ.ง.ด.53). total_amount = Σ actual transfers (net of WHT).';
COMMENT ON TABLE  payment.payout_batch_items IS
    'One row per booking PAID. booking_id UNIQUE is the paid-marker preventing a guard being paid twice for the same job.';
COMMENT ON COLUMN payment.payout_batch_items.transfer_amount IS
    'The actual PromptPay amount for this booking = income − wht (WHT is withheld + remitted to the Revenue Department separately).';
