-- pguard profile-service — guard document expiry tracking (web-admin "expiring" screen).
--
-- The guard onboarding docs live as nullable S3-key columns on profile.guard_profiles
-- (id_card_key, security_license_key, …). Those columns record PRESENCE, not validity dates.
-- This table adds the expiry dimension the "expiring documents" admin surface needs: one row
-- per (guard, document_type) carrying the document's expiry date + when the guard was last
-- reminded to renew. Kept SEPARATE from guard_profiles (rather than adding 5× expiry columns)
-- so the doc set can grow and a doc with no recorded expiry simply has no row.
--
-- Population is a FOLLOW-UP: the document-upload flow (S3 upload + expiry capture) is itself a
-- deferred slice, so this table starts empty — the endpoint + screen are real and ready, and
-- show nothing until capture lands (honest, not faked). No cross-service FK — guard_id is a
-- bare UUID owned by identity. Indexes inline (empty table at creation).

CREATE TABLE profile.document_expiry (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guard_id        UUID        NOT NULL,            -- owned by identity (no FK)
    -- Matches the onboarding doc set on guard_profiles (the passbook photo is a bank doc, not
    -- an expiring credential, so it is intentionally excluded).
    document_type   TEXT        NOT NULL
        CHECK (document_type IN (
            'id_card', 'security_license', 'training_cert', 'criminal_check', 'driver_license'
        )),
    expiry_date     DATE        NOT NULL,
    last_reminded_at TIMESTAMPTZ,                    -- NULL until a renewal reminder is sent
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (guard_id, document_type)
);

-- Hot path: the admin surface lists documents by soonest expiry within a window.
CREATE INDEX idx_document_expiry_date ON profile.document_expiry (expiry_date);
