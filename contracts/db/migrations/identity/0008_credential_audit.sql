-- pguard identity — credential-change audit (security-review follow-up on /auth/reset-pin).
--
-- profile.access_audit covers admin READS of PII; nothing recorded credential WRITES —
-- a password change or a forgot-PIN reset left no trail. This logs those, written in the
-- SAME transaction as the credential change itself.
--
-- Append-only BY CONVENTION: the app role is also the migration role (single-role
-- posture), so REVOKE UPDATE/DELETE cannot be enforced here yet — revisit when DB role
-- separation lands (Phase 5). Retention purges DELETE by created_at (see the index).
CREATE TABLE identity.credential_audit (
    id         BIGSERIAL   PRIMARY KEY,
    -- Same-service FK (identity.users) — allowed; only CROSS-service FKs are banned.
    -- Production never hard-deletes users (PDPA erasure soft-deletes + redacts), so the
    -- CASCADE only ever fires for test-fixture cleanup.
    user_id    UUID        NOT NULL REFERENCES identity.users(id) ON DELETE CASCADE,
    action     TEXT        NOT NULL,   -- 'password_changed' | 'pin_reset'
    detail     TEXT,                   -- optional channel/context (e.g. 'via_otp')
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Retention/query helpers: by time (purge/range) and by account (whose credentials changed).
CREATE INDEX idx_credential_audit_created_at ON identity.credential_audit (created_at);
CREATE INDEX idx_credential_audit_user ON identity.credential_audit (user_id, created_at DESC);
