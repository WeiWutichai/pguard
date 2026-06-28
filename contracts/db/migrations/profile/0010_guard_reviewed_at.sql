-- pguard profile-service — guard approval-decision timestamp (web-admin "avg approval time").
--
-- The admin dashboard wants the AVERAGE turnaround between a guard APPLYING and an admin
-- finalizing the decision (เวลาอนุมัติเฉลี่ย, #132). The application moment is already
-- `guard_profiles.created_at` (the first profile submit). The DECISION moment was NOT
-- recoverable: `set_approval_status` only bumps the generic `updated_at`, which any later
-- self-edit (the guard re-upserting a field after approval) would clobber — making it a wrong
-- proxy for "when was this approved". This adds a DEDICATED, write-once-by-admin column.
--
-- `reviewed_at` is stamped (= now()) ONLY when an admin moves the row out of `pending`
-- (approve or reject) — see repo::set_approval_status. It stays NULL while pending and is
-- never touched by a guard self-edit, so `reviewed_at - created_at` is a faithful approval
-- duration. The avg metric is computed over APPROVED rows only (the dashboard's "approval"
-- time), but the column is stamped on reject too so a future "review SLA" can include both.
--
-- ADDITIVE + nullable — no rewrite, no NOT NULL on the (effectively empty, dev) table.
-- Idempotent (`IF NOT EXISTS`) alongside the migrate.sh ledger. The avg query filters on
-- `reviewed_at IS NOT NULL AND approval_status = 'approved'`; the existing
-- idx_guard_profiles_approval_status covers the status predicate, and the metric is a low-
-- frequency dashboard read over a small finalized set, so no dedicated index is added.

ALTER TABLE profile.guard_profiles
    ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
