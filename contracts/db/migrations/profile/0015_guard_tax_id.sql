-- pguard profile-service — guard tax id (Thai national/tax id) for guard payouts.
--
-- The guard payout batch (SCB Business Net bulk-transfer file + ภ.ง.ด.53 withholding-tax
-- certificate, built by payment-service) needs the guard's 13-digit Thai national/tax id: it is
-- BOTH the ภ.ง.ด.53 recipient TIN AND the PromptPay "NAT" proxy the transfer is addressed to.
--
-- Stored PLAINTEXT here (the WHT cert + PromptPay NAT need the full value in the clear — it cannot
-- be one-way hashed), but treated as PDPA-sensitive: MASKED on the owner/admin profile READ exactly
-- like account_number, exposed in FULL only over the service-JWT'd internal payout-profile endpoint
-- (GET /internal/guards/{id}/payout-profile). Nullable — a guard who registered before this column,
-- or who has not supplied a tax id, is simply EXCLUDED from a WHT batch with a warning (never
-- silently dropped) rather than blocking the migration on a populated table.
--
-- ADDITIVE + nullable only — no rewrite, no NOT NULL on a populated table (CLAUDE.md Data).
-- IF NOT EXISTS keeps it idempotent alongside the migrate.sh ledger (applied without
-- --single-transaction). No index: a per-row attribute read WITH the profile / internal payout
-- read, never filtered on.
ALTER TABLE profile.guard_profiles
    ADD COLUMN IF NOT EXISTS tax_id TEXT;
