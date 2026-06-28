-- pguard identity-service — account security surface (#144 admin self-profile):
--   (1) TOTP 2FA (per-user encrypted secret + enabled flag + hashed recovery codes),
--   (2) admin API tokens (hash-at-rest, prefix-for-display, scoped, revocable),
--   (3) per-device sessions (device/IP/user-agent + last-seen on the refresh-token family).
--
-- All three are identity's OWN schema (CLAUDE.md "Data": only identity writes `identity`).
-- NO cross-service foreign keys — `user_id` references `identity.users.id` by bare UUID.
--
-- Index note (CLAUDE.md "Data"): these tables are EMPTY at creation (no prod users), so the
-- indexes are created INLINE / non-CONCURRENTLY here. A LATER additive index on a populated
-- table MUST use CREATE INDEX CONCURRENTLY in its own tx-free migration.

-- ─────────────────────────────────────────────────────────────────────────────
-- (1) TOTP 2FA — per-user secret + recovery codes.
-- ─────────────────────────────────────────────────────────────────────────────
--
-- `totp_secret_enc` holds the RFC-6238 seed SEALED with AES-256-GCM under the service-held
-- `TOTP_ENC_KEY` (never the bare base32 seed — a DB dump must not be replayable as 2FA). It is
-- populated during PROVISIONING (`POST /auth/2fa/setup`) and the account is NOT yet protected;
-- `totp_enabled` flips true only after the user proves possession of a live code at
-- `POST /auth/2fa/enable`. `totp_confirmed_at` stamps that enablement.
ALTER TABLE identity.users
    ADD COLUMN IF NOT EXISTS totp_secret_enc   BYTEA,
    ADD COLUMN IF NOT EXISTS totp_enabled      BOOLEAN     NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS totp_confirmed_at TIMESTAMPTZ;

-- One-time recovery codes (shown ONCE at enable; used to log in if the authenticator is lost).
-- Only the SHA-256 hash is stored (never the plaintext) — same hash-at-rest discipline as the
-- API tokens below. A row is consumed by stamping `used_at` (single-use); the hash stays so a
-- replay of the same code is rejected. Codes are deleted+regenerated whenever 2FA is re-enabled.
CREATE TABLE IF NOT EXISTS identity.totp_recovery_codes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL,                 -- owned by identity (no cross-service FK)
    code_hash   TEXT        NOT NULL,                 -- SHA-256 hex of the recovery code
    used_at     TIMESTAMPTZ,                          -- single-use: NULL = unused
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Verify path looks up an UNUSED code for a user by its hash.
CREATE INDEX IF NOT EXISTS idx_totp_recovery_user
    ON identity.totp_recovery_codes (user_id) WHERE used_at IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- (2) Admin API tokens — long-lived bearer credentials for admin API automation.
-- ─────────────────────────────────────────────────────────────────────────────
--
-- The FULL token (`pguard_<prefix>_<secret>`) is returned exactly ONCE at creation; only the
-- SHA-256 hash of the SECRET half is stored, so a DB dump cannot reconstruct a usable token.
-- `prefix` is the short public id shown in the listing (and the lookup key at verify time —
-- avoids hashing-then-table-scanning). `role` is the role the token authenticates AS (today the
-- creator's own role, admin); `revoked_at` is a soft-revoke (kept for audit). Verify stamps
-- `last_used_at` so an admin can spot a stale/forgotten token.
CREATE TABLE IF NOT EXISTS identity.api_tokens (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL,                -- owner (no cross-service FK)
    name         TEXT        NOT NULL,                -- human label ("CI deploy bot")
    token_hash   TEXT        NOT NULL,                -- SHA-256 hex of the secret half (NEVER plaintext)
    prefix       TEXT        UNIQUE NOT NULL,         -- public, displayed + the verify lookup key
    role         identity.user_role NOT NULL,         -- the role the token authenticates as
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ,
    revoked_at   TIMESTAMPTZ                          -- soft-revoke (NULL = live)
);
-- Owner listing (the admin's own tokens), newest first.
CREATE INDEX IF NOT EXISTS idx_api_tokens_user ON identity.api_tokens (user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- (3) Per-device sessions — device/IP/user-agent + last-seen on the refresh family.
-- ─────────────────────────────────────────────────────────────────────────────
--
-- v2 already tracks refresh families + rotation/reuse in `identity.refresh_tokens`; #144 adds the
-- device context so a user can SEE their active sessions and revoke ONE device. The columns hang
-- off every token row; the sessions list reads them per-family (the family's first row carries the
-- login context, `last_used_at` advances on rotation). `ip` is stored as text (may be masked in
-- the API response). Nullable — pre-existing rows + a login without a captured UA/IP are fine.
ALTER TABLE identity.refresh_tokens
    ADD COLUMN IF NOT EXISTS user_agent   TEXT,
    ADD COLUMN IF NOT EXISTS ip           TEXT,
    ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ;
