-- pguard profile-service — organization (company) profile settings (#143, Admin Settings →
-- "บริษัท / Company profile" tab).
--
-- WHY HERE (where org/company settings live): the company profile (company_name / tax_id /
-- address) is org-wide, ADMIN-OWNED config that is shown on RECEIPTS (payment service) and
-- IN-APP (mobile). It is NOT deploy-time env config (it is edited at runtime via the admin UI,
-- no redeploy), so unlike the other Settings tabs (payment-gateway/SMS/FCM/Storage/JWT/CORS —
-- those ARE env config) it needs a real persisted store. There was NO existing settings/org
-- store in v2. The profile service is the natural owner: it already hosts every admin-facing
-- surface behind `require_role(admin)`, owns the PDPA §30 access_audit sink + the outbox +
-- the replica-read pattern, and the gateway already routes `/admin/*` admin surfaces to it.
-- payment (receipts) + mobile (in-app) are CONSUMERS — per CLAUDE.md they read this via the
-- service's API (a service-JWT'd internal read), never by owning a copy of the table.
--
-- SINGLE-ROW table: an org has exactly one company profile. Enforced by a fixed primary key
-- `id BOOLEAN PRIMARY KEY DEFAULT TRUE` with a CHECK pinning it to TRUE — at most one row can
-- ever exist. The PUT handler upserts via `ON CONFLICT (id)`; the GET returns the row or a
-- typed "unset" empty default (the admin UI shows blank fields until first saved).
--
-- All columns NULLABLE: the admin saves the company profile incrementally (name first, tax_id
-- later, etc.), mirroring the rest of the profile slice (every profile field is optional). The
-- application layer validates lengths + a lenient tax_id format before writing.

CREATE TABLE IF NOT EXISTS profile.org_settings (
    -- Single-row guard: only `TRUE` is allowed, so the table holds at most one row.
    id           BOOLEAN     PRIMARY KEY DEFAULT TRUE CHECK (id),
    company_name TEXT,
    -- Thai TIN is 13 digits; stored as text (leading zeros, future formats). App validates a
    -- LENIENT format (digits/space/hyphen, bounded length) — not a checksum.
    tax_id       TEXT,
    address      TEXT,
    -- Audit who last touched the company profile + when (the admin user_id; no cross-service FK).
    updated_by   UUID,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- No index needed: the table is single-row, always read/written by its constant primary key.
