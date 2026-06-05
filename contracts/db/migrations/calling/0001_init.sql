-- pguard calling-service — schema init (Phase 3: split from v1 booking god-service).
--
-- WebRTC voice/video SIGNALING + the call audit log. The media plane is the Node mediasoup
-- SFU (brokered by calling over a service-JWT); this schema is signaling/persistence only.
--
-- Per-service schema ownership: ONLY calling-service writes to schema `calling` (CLAUDE.md
-- "Data"). NO cross-service foreign keys — `caller_id`, `callee_id`, `booking_id` are bare
-- UUIDs owned by identity/booking; the participant authz is verified at initiate via
-- booking's service-JWT'd internal read, never an FK.
--
-- v2 state set (simpler than v1, which also had `ringing`/`failed`):
--   initiated → accepted → connected → ended      (happy path)
--   initiated → rejected                          (callee declines)
--   initiated → missed                            (caller cancels before answer, via PUT /end)
--
-- NOTE: `missed` is currently caller/client-driven (ending an unanswered call). A SERVER-side
-- stale-ring sweeper (auto-`missed` after a ring timeout, no client action) is deferred to a
-- later slice; until then a never-cancelled ring stays `initiated`.

CREATE SCHEMA IF NOT EXISTS calling;

CREATE TYPE calling.call_status AS ENUM (
    'initiated',
    'accepted',
    'connected',
    'ended',
    'rejected',
    'missed'
);

CREATE TYPE calling.call_type AS ENUM ('audio', 'video');

CREATE TABLE calling.call_logs (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_id        UUID                 NOT NULL,            -- owned by identity (no FK)
    callee_id        UUID                 NOT NULL,            -- DERIVED from the booking (no FK)
    booking_id       UUID                 NOT NULL,            -- the assignment the call belongs to (no FK)
    call_type        calling.call_type    NOT NULL DEFAULT 'audio',
    status           calling.call_status  NOT NULL DEFAULT 'initiated',
    -- Lifecycle timestamps. `started_at` is row creation; the rest fill as the call advances.
    started_at       TIMESTAMPTZ          NOT NULL DEFAULT now(),
    answered_at      TIMESTAMPTZ,
    ended_at         TIMESTAMPTZ,
    duration_seconds INTEGER,
    end_reason       TEXT,
    created_at       TIMESTAMPTZ          NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ          NOT NULL DEFAULT now()
);

-- Hot paths: a participant's call history + the admin newest-first view.
CREATE INDEX idx_call_logs_caller ON calling.call_logs (caller_id, created_at DESC);
CREATE INDEX idx_call_logs_callee ON calling.call_logs (callee_id, created_at DESC);
CREATE INDEX idx_call_logs_booking ON calling.call_logs (booking_id);
-- The "callee already busy" guard + the stale-ringing sweep both filter on active status.
CREATE INDEX idx_call_logs_active
    ON calling.call_logs (callee_id)
    WHERE status IN ('initiated', 'accepted', 'connected');

-- Transactional outbox: the call state change AND its `pguard.events.calling.*` event row
-- are written in ONE transaction (CLAUDE.md "Cross-tx consistency"); a background relay
-- publishes to NATS so notification consumes (incoming-call / missed-call push). `payload`
-- is a fully-formed EventEnvelope.
CREATE TABLE calling.outbox (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic        TEXT        NOT NULL,            -- = EventEnvelope.event_type (NATS subject)
    payload      JSONB       NOT NULL,            -- the serialized EventEnvelope
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ
);

CREATE INDEX idx_calling_outbox_unpublished
    ON calling.outbox (created_at)
    WHERE published_at IS NULL;
