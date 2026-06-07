-- pguard identity — account approval lifecycle (registration gate).
--
-- v2 registration (POST /auth/register) creates accounts in a NON-loginable `pending`
-- state and returns 202 with NO tokens. identity owns account state (CLAUDE.md "identity
-- owns users.role and account state") — login + refresh gate on `approval_status = 'approved'`
-- so a pending/rejected account can never reach a protected endpoint.
--
-- The transition to 'approved' (admin vetting for guards; customer approval) is performed by
-- a FUTURE event-driven slice: profile-service owns the per-profile approval (profile.yaml's
-- approve/reject endpoints) and will emit an event that identity consumes to flip this column
-- — NO cross-schema write crosses the identity↔profile boundary.
--
-- Schema-qualified enum (mirrors profile.approval_status) so it never collides with another
-- service's `approval_status` type; the repo reads/writes it via an explicit ::text cast.
CREATE TYPE identity.approval_status AS ENUM ('pending', 'approved', 'rejected');

-- Default 'pending': a freshly INSERTed row is non-loginable until approved. The table holds
-- no production users (CLAUDE.md "no production users to protect"), so the default backfills
-- nothing of consequence. No index: login looks the row up by the UNIQUE phone/email and then
-- checks this one column on that single row — no separate index is needed for the auth path.
ALTER TABLE identity.users
    ADD COLUMN IF NOT EXISTS approval_status identity.approval_status NOT NULL DEFAULT 'pending';
