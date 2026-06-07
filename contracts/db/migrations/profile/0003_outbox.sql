-- pguard profile-service — transactional outbox (approval → login event propagation).
--
-- Admin approve/reject flips `profile.guard_profiles.approval_status` (this schema), but login
-- is gated on `identity.users.approval_status` (a DIFFERENT schema identity owns). Rather than a
-- forbidden cross-schema write, profile writes a `user.approved` event row into THIS outbox in
-- the SAME transaction as the status flip — atomic: approve + event, never one without the other.
-- A background relay drains the outbox to NATS JetStream; identity's durable consumer flips its
-- own column. Mirrors booking/calling/payment's outbox (CLAUDE.md "Transactional outbox").
CREATE TABLE profile.outbox (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic        TEXT        NOT NULL,            -- = EventEnvelope.event_type (NATS subject)
    payload      JSONB       NOT NULL,            -- the serialized EventEnvelope
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ
);

-- Relay polls only unpublished rows, oldest first.
CREATE INDEX idx_profile_outbox_unpublished
    ON profile.outbox (created_at)
    WHERE published_at IS NULL;
