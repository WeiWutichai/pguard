-- pguard identity — account deletion / erasure (PDPA §33, Phase 5 C5.2).
--
-- Soft-delete: the user row is RETAINED (minimal audit of WHEN the account was erased) but
-- PII is redacted (phone → opaque placeholder, email → NULL) and the account is deactivated
-- so it can never authenticate again. `deleted_at` records the erasure instant.
ALTER TABLE identity.users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
