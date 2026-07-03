-- pguard identity — credential-change audit (security-review follow-up on /auth/reset-pin).
--
-- profile.access_audit covers admin READS of PII; nothing recorded credential WRITES —
-- a password change or a forgot-PIN reset left no trail. This logs those (append-only),
-- written in the SAME transaction as the credential change itself.
CREATE TABLE identity.credential_audit (
    id         BIGSERIAL   PRIMARY KEY,
    user_id    UUID        NOT NULL,   -- the affected account (no cross-service FK)
    action     TEXT        NOT NULL,   -- 'password_changed' | 'pin_reset'
    detail     TEXT,                   -- optional channel/context (e.g. 'via_otp')
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Retention/query helpers: by time (purge/range) and by account (whose credentials changed).
CREATE INDEX idx_credential_audit_created_at ON identity.credential_audit (created_at);
CREATE INDEX idx_credential_audit_user ON identity.credential_audit (user_id, created_at DESC);
