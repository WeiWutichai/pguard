-- pguard profile-service — guard recruitment pipeline stage (web-admin "recruit" screen).
--
-- The guard onboarding flow already has the authoritative outcome on guard_profiles:
-- approval_status (pending → approved | rejected), the login gate. This adds a lightweight
-- PRE-approval PIPELINE position so the recruitment kanban can move a still-`pending` applicant
-- through workflow stages (sourcing → screened → docs_verified) before the admin's final
-- approve/reject. It is PURELY admin-workflow metadata — it gates nothing (approval_status
-- remains the only thing that unblocks login). Approved/rejected applicants leave the pipeline
-- via approval_status, so their recruitment_stage is irrelevant once finalized.
--
-- Dev note: guard_profiles is effectively empty (no production users — strangler-fig is
-- discipline-only here), so ADD COLUMN ... NOT NULL DEFAULT is a safe instant rewrite. A
-- self-registered guard who submitted a profile defaults to 'screened' (they have applied);
-- 'sourcing' is for admin-added leads (no add-candidate flow yet → that column stays empty).

CREATE TYPE profile.recruitment_stage AS ENUM ('sourcing', 'screened', 'docs_verified');

ALTER TABLE profile.guard_profiles
    ADD COLUMN recruitment_stage profile.recruitment_stage NOT NULL DEFAULT 'screened';
