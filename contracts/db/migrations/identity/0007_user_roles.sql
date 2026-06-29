-- pguard identity-service — multi-role support (Option A: one phone = one account that
-- can hold BOTH roles, guard + customer).
--
-- BACKGROUND: `identity.users.role` is a SINGLE enum and `phone` is UNIQUE, so today one
-- phone = one role. This migration adds `identity.user_roles` — the SET of APPROVED roles a
-- user holds — WITHOUT dropping `users.role` (kept as the registration/primary role for
-- backward compatibility: every existing JWT carries that role, and `/auth/login` keeps
-- minting it). A user becomes multi-role by enrolling a second role (POST /auth/roles →
-- pending second profile → on approval the role is INSERTed here).
--
-- Per-service schema ownership: ONLY identity-service writes `identity.*` (CLAUDE.md "Data").
-- No cross-service FK — `user_roles.user_id` references `identity.users(id)` (same schema).
--
-- The table is created EMPTY and immediately BACKFILLED from the existing `users`, so every
-- already-approved single-role user keeps their current role as an enrolled role with zero
-- behavioural change.

CREATE TABLE identity.user_roles (
    user_id    UUID               NOT NULL REFERENCES identity.users(id) ON DELETE CASCADE,
    role       identity.user_role NOT NULL,
    created_at TIMESTAMPTZ        NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role)
);

-- Reverse lookup "which roles does this user have" is the PK's leading column; the membership
-- check in /auth/switch-role + /auth/roles is `(user_id, role)` = a PK probe. No extra index.

-- BACKFILL: every existing user keeps their registration role as an enrolled role. This runs
-- once at migration time. `ON CONFLICT DO NOTHING` makes a re-run (or a racing approval event
-- that lands between this and a later deploy) idempotent. NOTE: a still-PENDING user is also
-- backfilled here — harmless, because login still gates on `users.approval_status` (a pending
-- account cannot authenticate at all), and the row matches what the approval event would later
-- insert anyway. The set of ENROLLED-AND-USABLE roles is therefore exactly the existing
-- single-role behaviour until a user actively enrolls a second role.
INSERT INTO identity.user_roles (user_id, role)
SELECT id, role FROM identity.users
ON CONFLICT (user_id, role) DO NOTHING;
