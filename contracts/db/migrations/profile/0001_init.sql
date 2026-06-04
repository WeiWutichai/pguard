-- pguard profile-service — schema init (guard/customer profiles slice).
--
-- Per-service schema ownership: ONLY profile-service writes to schema `profile`
-- (CLAUDE.md "Data"). `user_id` is owned by identity-service and referenced here by
-- BARE UUID — NO cross-service foreign key (CLAUDE.md "Don't: no new foreign keys
-- across service boundaries"). The application enforces that a profile's user exists.
--
-- Bank account + ID document data is PII (PDPA): the read API masks the account number
-- to its last 4 digits (admin endpoints may return the full value). Document *keys*
-- (S3 object paths) are kept nullable here so the deferred upload follow-up can fill
-- them — only keys + metadata live in Postgres; the binaries stay in S3 (CLAUDE.md).
--
-- Note on indexes: created inline because the tables are empty at creation. LATER
-- additive indexes on populated tables must use CREATE INDEX CONCURRENTLY
-- (CLAUDE.md "Data") in their own migration outside a transaction.

CREATE SCHEMA IF NOT EXISTS profile;

-- Guard onboarding approval lifecycle. Mirrors shared::models::ApprovalStatus
-- (pending | approved | rejected). Schema-qualified so it never collides with another
-- service's `approval_status` type; the repo reads it cast to text.
CREATE TYPE profile.approval_status AS ENUM ('pending', 'approved', 'rejected');

-- Guard applicant profile — one row per guard user (UNIQUE user_id), upserted by the
-- guard themselves. `approval_status` is owned here (an admin moves it via the pure
-- transition). Document-key columns are nullable placeholders for the deferred upload
-- slice (no upload is built yet).
CREATE TABLE profile.guard_profiles (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               UUID NOT NULL UNIQUE,            -- owned by identity; bare UUID, no cross-service FK
    gender                TEXT,
    date_of_birth         DATE,
    years_of_experience   INTEGER,
    previous_workplace    TEXT,
    -- Document object keys (S3 path; deferred upload slice fills these). Keys only —
    -- the binaries live in S3 (CLAUDE.md "Binary blobs stay in S3").
    id_card_key           TEXT,
    security_license_key  TEXT,
    training_cert_key     TEXT,
    criminal_check_key    TEXT,
    driver_license_key    TEXT,
    passbook_photo_key    TEXT,
    -- Bank account details (PII — masked on read).
    bank_name             TEXT,
    account_number        TEXT,
    account_name          TEXT,
    approval_status       profile.approval_status NOT NULL DEFAULT 'pending',
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Admin onboarding queue filters by approval_status (GET /admin/guard-profiles).
CREATE INDEX idx_guard_profiles_approval_status ON profile.guard_profiles (approval_status);

-- Customer profile — minimal in this slice (the customer registration flow expands it
-- later). One row per customer user (UNIQUE user_id), upserted by the customer.
CREATE TABLE profile.customer_profiles (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL UNIQUE,                    -- owned by identity; bare UUID, no cross-service FK
    full_name     TEXT,
    address       TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
