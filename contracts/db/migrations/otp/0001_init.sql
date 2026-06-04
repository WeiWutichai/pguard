-- pguard otp-service — schema init (OTP / phone-verification slice).
--
-- Per-service schema ownership: ONLY otp-service writes to schema `otp`
-- (CLAUDE.md "Data"). NO cross-service foreign keys — the verified phone is handed to
-- profile/identity via the single-use phone-verified JWT, never by a DB reference.
--
-- Only the SHA-256 HASH of each OTP code is stored (never plaintext), so a DB dump or
-- backup leak cannot reveal a live code. Abuse-control counters (captcha, cooldown,
-- daily cap, tiered lockout, phone-verify jti) live in Redis, not here.
--
-- Note on indexes: created inline because the table is empty at creation. LATER additive
-- indexes on populated tables must use CREATE INDEX CONCURRENTLY (CLAUDE.md "Data") in
-- their own migration outside a transaction.

CREATE SCHEMA IF NOT EXISTS otp;

CREATE TABLE otp.otp_codes (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    phone      TEXT        NOT NULL,
    -- SHA-256 hex of the OTP code. NEVER the plaintext code.
    code_hash  TEXT        NOT NULL,
    -- What the verified phone unlocks (e.g. 'register'). Keeps room for future flows.
    purpose    TEXT        NOT NULL DEFAULT 'register',
    -- Verify attempts, incremented atomically (UPDATE ... FOR UPDATE) per try.
    attempts   INTEGER     NOT NULL DEFAULT 0,
    is_used    BOOLEAN     NOT NULL DEFAULT FALSE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The verify hot path selects the latest live code for a phone:
--   WHERE phone = $1 AND purpose AND is_used = false AND expires_at > now()
--   ORDER BY created_at DESC LIMIT 1 FOR UPDATE
-- (phone, created_at) covers the lookup + ordering.
CREATE INDEX idx_otp_codes_phone_created_at ON otp.otp_codes (phone, created_at DESC);
