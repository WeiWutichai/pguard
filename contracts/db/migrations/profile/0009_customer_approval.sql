-- pguard profile-service — customer admin-approval gate.
--
-- Customers previously AUTO-APPROVED: the first customer_profiles insert enqueued a
-- `user.approved` outbox event, so identity flipped its own approval_status and the account
-- became loginable with no human review. v2 switches hirers to the SAME admin-review gate guards
-- already use (set_*_approval flips approval_status + emits user.approved/rejected in one tx).
-- This adds the approval_status column customers were missing — they now start `pending` and an
-- admin approves/rejects via POST /admin/customer-profiles/{user_id}/{approve,reject}, mirroring
-- guard_profiles (which carries the same profile.approval_status ENUM = pending|approved|rejected,
-- see 0001_init.sql).
--
-- CRITICAL BACKFILL: rows that already exist were auto-approved under the OLD flow, so they MUST
-- stay loginable — backfill them to 'approved'. NEW rows must default to 'pending' (the gate).
-- Two statements achieve both: ADD COLUMN with a transient DEFAULT 'approved' (so every existing
-- row is backfilled approved in the instant rewrite), THEN flip the column default to 'pending'
-- so all future inserts start un-approved. The repo INSERT does not set approval_status — the
-- 'pending' default applies — and a self-edit (ON CONFLICT) never touches it.
--
-- Dev note: customer_profiles is effectively empty (no production users — strangler-fig is
-- discipline-only here), so ADD COLUMN ... NOT NULL DEFAULT is a safe instant rewrite.

ALTER TABLE profile.customer_profiles
    ADD COLUMN approval_status profile.approval_status NOT NULL DEFAULT 'approved';
ALTER TABLE profile.customer_profiles
    ALTER COLUMN approval_status SET DEFAULT 'pending';

-- Admin customer-review queue filters by approval_status (GET /admin/customer-profiles). The
-- table is now populated, so this additive index is created CONCURRENTLY (CLAUDE.md "Data");
-- migrate.sh applies each file in autocommit (no wrapping tx), so CONCURRENTLY is supported.
CREATE INDEX CONCURRENTLY idx_customer_profiles_approval_status
    ON profile.customer_profiles (approval_status);
