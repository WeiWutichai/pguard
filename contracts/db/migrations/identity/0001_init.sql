-- pguard identity-service — schema init (auth foundation slice).
--
-- Per-service schema ownership: ONLY identity-service writes to schema `identity`
-- (CLAUDE.md "Data"). Identity is the system of record for users + the access JWTs
-- everything else validates. NO cross-service foreign keys — other aggregates
-- (bookings, payments, ...) reference `users.id` by bare UUID, never via FK.
--
-- Note on indexes: created inline because the tables are empty at creation. LATER
-- additive indexes on populated tables must use CREATE INDEX CONCURRENTLY
-- (CLAUDE.md "Data") in their own migration outside a transaction.

CREATE SCHEMA IF NOT EXISTS identity;

-- Role enum. Mirrors shared::models::UserRole (admin | customer | guard).
CREATE TYPE identity.user_role AS ENUM ('admin', 'customer', 'guard');

CREATE TABLE identity.users (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone                    TEXT        UNIQUE NOT NULL,
    email                    TEXT        UNIQUE,
    password_hash            TEXT        NOT NULL,
    role                     identity.user_role NOT NULL,
    -- Bumped to force-revoke ALL of a user's outstanding access tokens at once
    -- (CLAUDE.md "Token revocation": per-user version + jti blocklist). Validators
    -- that cache claims compare this against the version embedded at issuance.
    token_revocation_version INTEGER     NOT NULL DEFAULT 0,
    is_active                BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Login lookups are by phone or email; both are UNIQUE (indexed implicitly), so no
-- extra index is required for the auth hot path.

-- Refresh-token rotation ledger (RFC 6749 §6 + reuse detection — CLAUDE.md
-- "Refresh rotation"). One row per issued refresh token. A `family_id` groups every
-- rotation descended from a single login; `rotation_id` identifies a specific token
-- in that family. The opaque token the client holds is `{rotation_id}.{secret}`;
-- only the Argon2 hash of `secret` is stored (never plaintext), so a DB dump cannot
-- be replayed. Lookup is by `rotation_id` (indexed), then the secret is Argon2-verified.
-- A presented `rotation_id` whose row is already `revoked` (because it was rotated or
-- the family was killed) is treated as token REUSE => revoke the whole family.
CREATE TABLE identity.refresh_tokens (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID        NOT NULL,            -- owned by identity (same schema; no cross-service FK)
    family_id     UUID        NOT NULL,
    rotation_id   UUID        UNIQUE NOT NULL,     -- public part of the opaque token; lookup key
    jti           UUID        NOT NULL,            -- unique id of THIS token (revocation bookkeeping)
    secret_hash   TEXT        NOT NULL,            -- Argon2 PHC hash of the random secret half
    expires_at    TIMESTAMPTZ NOT NULL,
    revoked       BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Refresh hot paths: validate by rotation_id, rotate/revoke by family.
CREATE INDEX idx_refresh_tokens_family ON identity.refresh_tokens (family_id);
CREATE INDEX idx_refresh_tokens_user ON identity.refresh_tokens (user_id);
