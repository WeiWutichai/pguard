-- pguard profile-service — support tickets (H1, mobile "แจ้งปัญหา / ส่งความคิดเห็น").
--
-- WHY HERE (why profile owns the support-ticket surface): a ticket is user-adjacent data —
-- it records WHO (the reporter's user_id, owned by identity; bare UUID, no cross-service FK)
-- reported WHAT, and when. The profile service already hosts every user-facing + admin-facing
-- surface behind `require_role(...)`, owns the replica-read + admin-list pattern the tickets
-- list reuses, and the gateway already routes `/admin/*` here — so hosting the ticket surface
-- here avoids a new service and any cross-schema write. The mobile Help page POSTs a ticket;
-- an admin reads the newest-first list.
--
-- MINIMAL by design (the H1 request "make it a real TICKET"): a reporter, a kind (problem or
-- feedback), the free-text message (capped), an `open` status, and the created time. No triage
-- workflow / assignment / threading yet — those are follow-ups if the surface grows.

CREATE TABLE IF NOT EXISTS profile.support_tickets (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The reporter (identity-owned; bare UUID, no cross-service FK — same convention as
    -- guard_profiles.user_id). Resolved to a display name by the admin name-resolver on read.
    user_id    UUID        NOT NULL,
    -- Two buckets only: a problem report vs. a feedback/suggestion. CHECK-constrained so an
    -- unknown kind can never land (the app also validates before the write → typed 400).
    kind       TEXT        NOT NULL CHECK (kind IN ('problem', 'feedback')),
    -- The report body. Capped at 2000 chars at the DB boundary (defence in depth — the app
    -- validates length first); non-empty is enforced by the application layer.
    message    TEXT        NOT NULL CHECK (char_length(message) <= 2000),
    -- Lifecycle: 'open' on creation. Kept as free TEXT (no workflow enum yet) so a future
    -- triage slice can add states without a type migration; defaults to 'open'.
    status     TEXT        NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The admin list reads newest-first (ORDER BY created_at DESC). Index it — the table is empty
-- at creation so the inline (non-CONCURRENT) create is safe here (CLAUDE.md: later additive
-- indexes on populated tables must use CREATE INDEX CONCURRENTLY in their own migration).
CREATE INDEX idx_support_tickets_created_at ON profile.support_tickets (created_at DESC);
