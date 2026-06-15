-- pguard notification-service — admin automation rules (web-admin "automation" screen).
--
-- Stores admin-authored "when TRIGGER [if CONDITION] then ACTION" rules + an enable toggle.
-- Hosted in notification (not a new microservice): the canonical action is "notify", and
-- notification already consumes the NATS event bus the triggers map to.
--
-- SCOPE (honest): this is the AUTHORING + storage surface — create / list / toggle / delete.
-- LIVE EXECUTION (a consumer that evaluates enabled rules on each event and fires the action)
-- is a deliberate FOLLOW-UP: wiring rules into the event path is a production-behavior change
-- that warrants its own slice + decision. So a stored rule is inert until that lands — the
-- screen says so plainly rather than implying rules already fire. trigger/action are text keys
-- from a fixed admin-facing set (validated in the handler); condition is free descriptive text.
--
-- No cross-service FK — created_by is a bare UUID owned by identity. Index inline (empty table).

CREATE TABLE notification.automation_rules (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trigger_key    TEXT        NOT NULL,            -- e.g. missed_checkin | booking_cancelled
    condition_text TEXT,                            -- optional free-text condition
    action_key     TEXT        NOT NULL,            -- e.g. notify_admins | flag_guard
    is_enabled     BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by     UUID        NOT NULL,            -- admin user_id (owned by identity; no FK)
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Rule list, newest first.
CREATE INDEX idx_automation_rules_created ON notification.automation_rules (created_at DESC);
