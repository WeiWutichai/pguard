-- pguard profile — admin read-access audit (PDPA §30, Phase 5 C5.2).
--
-- v1's `audit.audit_logs` recorded WRITES, not reads. PDPA §30 expects a trail of WHO
-- ACCESSED personal data. This logs admin GETs of guard profiles (name / DOB / address /
-- bank account / document references) — the highest-PII admin read surface.
CREATE TABLE profile.access_audit (
    id          BIGSERIAL   PRIMARY KEY,
    accessed_by UUID        NOT NULL,   -- the admin user (no cross-service FK)
    action      TEXT        NOT NULL,   -- e.g. 'admin_list_guard_profiles'
    target      TEXT,                   -- optional scope (e.g. the approval-status filter)
    accessed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Retention/query helpers: by time (purge/range) and by admin (who-accessed-what).
CREATE INDEX idx_access_audit_accessed_at ON profile.access_audit (accessed_at);
CREATE INDEX idx_access_audit_by ON profile.access_audit (accessed_by, accessed_at DESC);
