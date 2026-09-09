-- pguard payment-service — GUARD PAYOUT: the two config columns SCB actually demands, and the
-- uniqueness the BANK's de-dup key needs.
--
-- Three defects, one migration (they all live on the payout config / batch header):
--
-- (a) `fee_charge_code` — `TXNDET` field 8 went out BLANK. The toolkit sources it from
--     `colFeeChargeCode` (doc line 1721) and `ValidCreditMandatory` lists `colFeeCharge` in the
--     UNCONDITIONAL required set (doc line 1915) — unlike the service type and the branch code,
--     which get explicit per-product exemptions right there (doc lines 1916-1922). If SCB's own
--     parser enforces the same rule, EVERY file we have ever produced bounces. Default `OUR`
--     ("payer bears the fee", `Master_data!TBFeeOther` = BEN/OUR for the PPY family — doc lines 314,
--     1997): a payroll-style payout means the company eats the transfer fee, and it is the only
--     value that keeps the guard receiving EXACTLY `payout_batch_items.transfer_amount`. `BEN` would
--     have the bank deduct its fee from the guard's credit, so the ledger and the bank statement
--     would disagree about what the guard was paid.
--
-- (b) `sms_notify` — the guard's LOGIN PHONE was being sent to SCB as an SMS-notify number
--     (`TXNDET` fields 9/10) the moment the payout profile started carrying a phone at all. Nobody
--     opted into that: SCB bills per SMS and the number leaves the platform on every payout run. It
--     is now an explicit, OFF-BY-DEFAULT choice. NOTE the phone is used for TWO unrelated things and
--     only ONE of them is gated here: it is still the PromptPay MOB fallback DESTINATION for a guard
--     with no tax id (that is how the money reaches them), and that must never be switched off by a
--     notification preference.
--
-- (c) `uq_payout_batches_file_ref` — `batch_ref` is a 12-digit timestamp at ONE-SECOND resolution
--     and `file_ref` is that stamp plus the product code, yet the only index on the table was the
--     primary key. Two exports committed in the same Bangkok second with DISJOINT guard selections
--     never trip the per-booking paid-marker, so both used to succeed and produce two files sharing
--     the customer transaction refs SCB de-dups on. The unique makes the loser's whole transaction
--     roll back — nothing marked paid, a typed 409 telling the admin to retry in a moment.
--
-- Per-service schema ownership: ONLY payment writes schema `payment`. No cross-service FKs.
-- IDEMPOTENT (CLAUDE.md): ADD COLUMN IF NOT EXISTS / CREATE INDEX IF NOT EXISTS / duplicate_object
-- catches throughout, so applying it twice is a no-op, and it is safe WITHOUT --single-transaction.

-- ── (a) the fee-charge code ──────────────────────────────────────────────────────────────────
ALTER TABLE payment.payout_config
    ADD COLUMN IF NOT EXISTS fee_charge_code TEXT NOT NULL DEFAULT 'OUR';

-- The vocabulary is closed to the `TBFeeOther` pair (doc line 314). `SHA` is deliberately absent:
-- it belongs to `TBFeeBNT` (BAHTNET, doc line 312), a product pguard does not ship.
DO $$ BEGIN
    ALTER TABLE payment.payout_config
        ADD CONSTRAINT chk_payout_config_fee_charge_code
            CHECK (fee_charge_code IN ('BEN', 'OUR'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── (b) the SMS-notify opt-in ────────────────────────────────────────────────────────────────
ALTER TABLE payment.payout_config
    ADD COLUMN IF NOT EXISTS sms_notify BOOLEAN NOT NULL DEFAULT FALSE;

-- ── (c) one file ref, one file ───────────────────────────────────────────────────────────────
-- NOT `CONCURRENTLY` (matching 0007/0009's plain-index style): this table holds one row per
-- generated payout file and is written only by an admin export, so the brief lock is free — while a
-- CONCURRENTLY build that fails would leave an INVALID index that the `IF NOT EXISTS` on a re-apply
-- silently skips, leaving the de-dup guard permanently off on a money table.
--
-- If this statement FAILS with a uniqueness error, the database already holds two batches sharing a
-- file ref — i.e. the bug above already happened and two files carrying the same customer
-- transaction refs are out there. That must be looked at by a human (which file did the bank take?),
-- so the migration is deliberately left to fail loudly rather than de-duplicating money rows on its
-- own initiative.
CREATE UNIQUE INDEX IF NOT EXISTS uq_payout_batches_file_ref
    ON payment.payout_batches (file_ref);

COMMENT ON COLUMN payment.payout_config.fee_charge_code IS
    'TXNDET field 8 — who bears the transfer fee (Master_data!TBFeeOther: OUR = payer/company, BEN = recipient/guard). Mandatory for every credit row (ValidCreditMandatory). Default OUR: BEN would make the guard receive LESS than payout_batch_items.transfer_amount records, so our ledger and the bank would disagree.';
COMMENT ON COLUMN payment.payout_config.sms_notify IS
    'Opt-in for TXNDET fields 9/10 (SMS notify flag + number). OFF by default: SCB bills per SMS and the number is the guard''s login phone. Does NOT affect the PromptPay MOB fallback — the same phone still addresses the money when a guard has no tax id.';
COMMENT ON INDEX payment.uq_payout_batches_file_ref IS
    'One SCB file per file ref. batch_ref is a 1-second-resolution timestamp, so two exports in the same second would otherwise commit two files sharing the customer transaction refs the bank de-dups on.';
