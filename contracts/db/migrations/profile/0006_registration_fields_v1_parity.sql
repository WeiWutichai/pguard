-- pguard profile-service — registration fields = v1 parity.
--
-- Brings the fields captured at guard/customer registration up to v1 parity (field names match
-- v1 `auth.guard_profiles` / `auth.customer_profiles` exactly — see
-- ../guard-dispatch/services/auth/src/models.rs GuardProfileRow / CustomerProfileRow).
--
-- v2 stores the guard's name on the profile (not on identity.users like v1), so `full_name`
-- lands here. Emergency-contact fields + address were absent in v2. Customer was missing
-- company_name / email / contact_phone (full_name + address already exist).
--
-- ADDITIVE + nullable only — no rewrite, no NOT NULL on a populated table (CLAUDE.md Data).
-- `IF NOT EXISTS` keeps it idempotent alongside the migrate.sh ledger. No index needed
-- (these are per-row attributes read with the profile, not filtered on).

ALTER TABLE profile.guard_profiles
    ADD COLUMN IF NOT EXISTS full_name                      TEXT,
    ADD COLUMN IF NOT EXISTS address                        TEXT,
    ADD COLUMN IF NOT EXISTS emergency_contact_name         TEXT,
    ADD COLUMN IF NOT EXISTS emergency_contact_phone        TEXT,
    ADD COLUMN IF NOT EXISTS emergency_contact_relationship TEXT;

ALTER TABLE profile.customer_profiles
    ADD COLUMN IF NOT EXISTS company_name  TEXT,
    ADD COLUMN IF NOT EXISTS email         TEXT,
    ADD COLUMN IF NOT EXISTS contact_phone TEXT;
