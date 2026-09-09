-- pguard payment-service — GUARD PAYOUT: the PER-TRANSACTION transfer cap.
--
-- SCB rejects a credit line whose amount exceeds the product's per-transaction limit, and a rejected
-- line is worse than an excluded one: the whole file bounces AFTER the bookings were already marked
-- paid. So the cap lives here, is read by the aggregation, and a guard whose TOTAL transfer would
-- exceed it is EXCLUDED with a Thai reason (the admin splits them across runs) — never written into
-- a money file and never silently dropped.
--
-- WHY IT IS CONFIGURABLE (the doc conflict): `docs/reviews/CPX_Toolkit_Reverse_Engineering.md` reads
-- as a contradiction — §15.10 / line 723 say the PromptPay cap is ฿10,000 while line 409 / 722 say
-- ฿2,000,000. §7.4/§7.5 (doc lines 2052-2060) resolve it: the toolkit stamps the proxy TYPE from the
-- credit-account LENGTH (15→EWL, 13→NAT, 10→MOB) and only a 15-digit E-Wallet proxy takes
-- `ValidateAmountPromptpay(0.01, 10000)`; every other length takes `ValidateAmountSmart` = ฿2,000,000.
-- Guards are paid on a 13-digit NAT (national id) or a 10-digit MOB (phone) proxy, so ฿2,000,000 is
-- their cap and ฿10,000 never applies. It stays a COLUMN rather than a constant so the limit can be
-- tightened (or corrected against what SCB actually enforces on this account) without a deploy.
--
-- NULL = no cap enforced. IDEMPOTENT (CLAUDE.md): ADD COLUMN IF NOT EXISTS + a duplicate_object catch
-- on the CHECK, so it can be applied more than once and WITHOUT --single-transaction.

ALTER TABLE payment.payout_config
    ADD COLUMN IF NOT EXISTS max_transfer_per_txn NUMERIC(12,2) DEFAULT 2000000;

-- A negative cap would exclude every guard silently; a zero cap is a deliberate "pay nobody" freeze
-- and stays allowed.
DO $$ BEGIN
    ALTER TABLE payment.payout_config
        ADD CONSTRAINT chk_payout_config_max_transfer_nonneg
            CHECK (max_transfer_per_txn IS NULL OR max_transfer_per_txn >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN payment.payout_config.max_transfer_per_txn IS
    'Per-transaction transfer cap (THB). Default 2000000 = the SMART/ORFT/PromptPay NAT+MOB limit; the ฿10,000 figure in the toolkit docs is the 15-digit E-Wallet (EWL) proxy limit only (doc §7.4/§7.5). A guard over the cap is EXCLUDED from the batch with a reason, never written as an over-limit line. NULL = no cap.';

-- The two batch references were previously built the wrong way round (0007's inline comments still
-- describe the old shapes). Restate them at the schema level so the columns document themselves:
-- the BATCH ref is the bare 12-digit stamp (the Customer Batch Ref is capped at 12 chars) and the
-- FILE ref is that stamp plus the product code. The `SCB_file_reference_…` string is only the
-- suggested DOWNLOAD NAME and belongs in neither column.
COMMENT ON COLUMN payment.payout_batches.batch_ref IS
    'BCHDET field 1 — the customer BATCH ref: the bare 12-digit DDMMYYHHMMSS Bangkok stamp. Capped at 12 characters, so the product code is NOT appended here.';
COMMENT ON COLUMN payment.payout_batches.file_ref IS
    'HEADER field 1 — the customer FILE ref = batch_ref || product_code (e.g. 050926120000PPY). NOT the download filename.';
