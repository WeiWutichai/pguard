-- pguard calling-service — call-EVENTS read model (#135).
--
-- WHY: `call_logs` keeps only the LATEST status + a handful of lifecycle timestamps. The admin
-- call-detail view wants the per-call TIMELINE — the ordered sequence of lifecycle milestones
-- (ringing → accepted/rejected → connected → ended) WITH the time each occurred, plus the
-- signaling steps the relay actually observes (offer/answer/ICE-candidate relayed, and whether
-- the peer was reachable). This is a derived AUDIT read model: an append-only event log keyed by
-- call_id, written by the SAME calling-service that owns `call_logs` (per-service schema
-- ownership — no cross-service FK; `call_id` references calling's own `call_logs.id`).
--
-- NOT in scope (cannot be observed by a signaling relay): media QUALITY — jitter, packet loss,
-- bitrate, MOS. Those live in the SFU/TURN stats plane (mediasoup `getStats` / coturn metrics),
-- which is not wired into the calling service. This table deliberately stores NO quality columns;
-- fabricating them would be misleading. See the FLAG in the slice report.
--
-- IDEMPOTENT writes: lifecycle transitions are recorded with a deterministic `dedupe_key`
-- (`<call_id>:<event_type>` for the once-per-call milestones) so a retried REST control call or a
-- replayed step does NOT double-append. Signaling relays (offer/answer/ice/peer-offline) CAN recur
-- legitimately (ICE trickles many candidates), so those carry NO dedupe_key (NULL) and always
-- append — the UNIQUE index ignores NULLs.

-- The kinds of events the relay/control plane can OBSERVE. Lifecycle milestones come from the
-- REST control endpoints (authoritative state machine); signaling steps come from the WS relay as
-- it forwards frames. (Stored as TEXT-checked, not a PG enum, so a later step type is an additive
-- migration with no ALTER TYPE — same trade-off the chat/notification slices make.)
--   ringing      — call row created (initiated); the callee is being rung
--   accepted     — callee accepted (initiated → accepted)
--   rejected     — callee declined (initiated → rejected)
--   connected    — media reported flowing (accepted → connected)
--   ended        — call ended after answer (→ ended)
--   missed       — call ended before answer / ring timeout (→ missed)
--   offer        — caller's SDP offer relayed to the callee (signaling, observed by the relay)
--   answer       — callee's SDP answer relayed to the caller (signaling)
--   ice_candidate— an ICE candidate relayed between peers (signaling; trickled, may recur)
--   peer_offline — a signaling frame could not be delivered (peer had no live socket)

CREATE TABLE calling.call_events (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id     UUID        NOT NULL REFERENCES calling.call_logs (id) ON DELETE CASCADE,
    event_type  TEXT        NOT NULL CHECK (event_type IN (
                    'ringing', 'accepted', 'rejected', 'connected', 'ended', 'missed',
                    'offer', 'answer', 'ice_candidate', 'peer_offline')),
    -- WHO this milestone/step is attributed to (caller or callee), when known. NULL for steps
    -- with no single actor. Bare UUID owned by identity (no cross-service FK).
    actor_id    UUID,
    -- Free-form structured detail (e.g. end_reason, the relay's "from"/"to" for a signal). Small
    -- JSON; NEVER the raw SDP/ICE blob (privacy + size) — only metadata about the step.
    detail      JSONB,
    -- Idempotency guard for the once-per-call lifecycle milestones. `<call_id>:<event_type>`.
    -- NULL for legitimately-repeatable signaling steps (the UNIQUE index ignores NULLs).
    dedupe_key  TEXT,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The hot read: one call's timeline in chronological order.
CREATE INDEX idx_call_events_call ON calling.call_events (call_id, occurred_at);

-- Idempotency: a given lifecycle milestone is recorded at most ONCE per call. Partial (NULLs
-- excluded) so repeatable signaling steps are unconstrained.
CREATE UNIQUE INDEX uq_call_events_dedupe
    ON calling.call_events (dedupe_key)
    WHERE dedupe_key IS NOT NULL;
