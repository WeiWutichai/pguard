-- pguard identity-service — admin/user display name + trigram search indexes (#144 / #138 / #142).
--
-- Adds a nullable `display_name` so an account (notably an ADMIN, which has no profile row in the
-- profile service) carries a human-readable name. Until now identity.users held only
-- id/phone/email/role, so `/auth/me` could return nothing but {user_id, role} and the admin
-- name-resolver had to omit admin ids entirely. With this column:
--   - GET /auth/me returns display_name + email,
--   - PUT /auth/me lets the caller set their own display_name + email,
--   - POST /internal/users/names resolves ANY user's {role, display_name} for the profile
--     resolver merge (admin names on the web admin lists / Activity Log #142),
--   - GET /admin/users/search finds users by name/phone/email across roles (#138 per-user notify).
--
-- Index note (CLAUDE.md "Data"): the table is empty in this environment (no prod users), so the
-- trigram GIN indexes are created INLINE / non-CONCURRENTLY here. A LATER additive index on a
-- populated table MUST use CREATE INDEX CONCURRENTLY in its own tx-free migration.

ALTER TABLE identity.users ADD COLUMN IF NOT EXISTS display_name TEXT;

-- Trigram (pg_trgm) GIN indexes back the case-insensitive substring search in
-- GET /admin/users/search (ILIKE '%q%' on display_name + phone). Without trigram support an
-- unanchored ILIKE is a full scan.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_users_display_name_trgm
    ON identity.users USING gin (display_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_users_phone_trgm
    ON identity.users USING gin (phone gin_trgm_ops);
