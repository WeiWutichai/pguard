-- pguard chat-service — schema init (port of v1 chat, N+1 fixed, v2-decoupled).
--
-- 1:1 booking-scoped messaging (customer ↔ assigned guard) + image/video attachments + the
-- transactional outbox that feeds `pguard.events.chat.message_sent`.
--
-- Per-service schema ownership: ONLY chat-service writes to schema `chat` (CLAUDE.md "Data").
-- NO cross-service foreign keys — `request_id`, `user_id`, `sender_id`, `uploader_id` are bare
-- UUIDs owned by booking/identity. Intra-schema FKs (conversation_id) ARE used for integrity.
--
-- v2 vs v1 (the two headline fixes):
--   * NO cross-schema JOIN. v1's `list_conversations` JOINed `auth.users` + `booking.*` to
--     resolve the counterpart name/avatar/status. v2 DENORMALIZES that booking-derived display
--     data onto `chat.participants` (display_name, avatar_url, user_role) + `conversations`
--     (request_status), supplied by the creator and refreshed via API/events — so the enriched
--     list is ONE query inside `chat` (no N+1, no cross-schema reach).
--   * NO fire-and-forget cross-schema INSERT. v1 spawned a task that INSERTed into
--     `notification.notification_logs`. v2 enqueues a `chat.outbox` row in the SAME tx as the
--     message and a relay publishes it; notification CONSUMES the event (CLAUDE.md outbox rule).

CREATE SCHEMA IF NOT EXISTS chat;

-- Message kinds. `image`/`video` carry the attachment reference/URL in `content`. Schema-
-- qualified enum; the repo binds it with a `::chat.message_type` cast and reads it back as
-- text, keeping the `domain` layer DB-free (mirrors calling.call_status).
CREATE TYPE chat.message_type AS ENUM ('text', 'image', 'video', 'system');

-- A conversation linked to a booking request. `request_status` is the booking's lifecycle
-- status, DENORMALIZED here to drive the server-side read-only gate (writes to a
-- completed/cancelled conversation are rejected) without a cross-schema read on the hot path.
CREATE TABLE chat.conversations (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id     UUID        NOT NULL,            -- the booking (bare UUID, no cross-svc FK)
    request_status VARCHAR(20),                     -- booking-derived; NULL ⇒ treated writable
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The internal status-push + request-scoped lookups filter on request_id.
CREATE INDEX idx_chat_conversations_request ON chat.conversations (request_id);

-- Conversation participants with their booking-derived role + (denormalized) display data.
-- A user appears once per conversation; the SAME user may be a guard in one conversation and a
-- customer in another (role is per-conversation). `user_role` drives alignment + per-role
-- receipts; `display_name`/`avatar_url` let the enriched list resolve the counterpart name with
-- NO cross-schema JOIN (CLAUDE.md → "Cross-service reads via API (or events for derived state)").
CREATE TABLE chat.participants (
    conversation_id UUID        NOT NULL REFERENCES chat.conversations (id) ON DELETE CASCADE,
    user_id         UUID        NOT NULL,           -- owned by identity (no cross-svc FK)
    user_role       VARCHAR(20) NOT NULL,           -- 'guard' | 'customer'
    display_name    VARCHAR(200),                   -- booking-derived (denormalized)
    avatar_url      TEXT,                           -- booking-derived (denormalized)
    PRIMARY KEY (conversation_id, user_id)
);

-- Membership lookups: list-conversations filters (user_id, user_role); the WS prefetch lists a
-- user's conversations by user_id (leading column). The PK covers the counterpart LATERAL
-- (conversation_id prefix).
CREATE INDEX idx_chat_participants_user ON chat.participants (user_id, user_role);

-- Messages. `sender_role` ('guard'/'customer') drives bubble alignment + the unread count —
-- alignment is by ROLE, never by sender_id (the same user is guard in one convo, customer in
-- another).
CREATE TABLE chat.messages (
    id              UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID              NOT NULL REFERENCES chat.conversations (id) ON DELETE CASCADE,
    sender_id       UUID              NOT NULL,     -- owned by identity (no cross-svc FK)
    sender_role     VARCHAR(20)       NOT NULL,     -- 'guard' | 'customer'
    content         TEXT,
    message_type    chat.message_type NOT NULL DEFAULT 'text',
    created_at      TIMESTAMPTZ       NOT NULL DEFAULT now()
);

-- The hot path: newest-first history + the last-message / unread correlated subqueries.
CREATE INDEX idx_chat_messages_conversation_time
    ON chat.messages (conversation_id, created_at DESC);

-- Per-ROLE read receipts: the same user reading as guard vs customer is tracked separately
-- (PK includes user_role). `read_at` anchors the unread count (messages newer than read_at).
CREATE TABLE chat.read_receipts (
    conversation_id      UUID        NOT NULL REFERENCES chat.conversations (id) ON DELETE CASCADE,
    user_id              UUID        NOT NULL,
    user_role            VARCHAR(20) NOT NULL,
    last_read_message_id UUID,                       -- newest message at read time (informational)
    read_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (conversation_id, user_id, user_role)
);

-- Attachments are CONVERSATION-scoped (`chat_id`), decoupled from a specific message row (v2
-- schema). The object key is `chat/{chat_id}/{uuid}.{ext}`; `file_url` holds the last presigned
-- URL (informational — a fresh one is generated on every read). The bucket is never exposed.
CREATE TABLE chat.attachments (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id     UUID         NOT NULL REFERENCES chat.conversations (id) ON DELETE CASCADE,
    uploader_id UUID         NOT NULL,               -- owned by identity (no cross-svc FK)
    file_key    TEXT         NOT NULL,               -- chat/{chat_id}/{uuid}.{ext}
    file_url    TEXT,                                -- last presigned URL (expires; regenerated)
    file_size   INTEGER,
    mime_type   VARCHAR(100) NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_chat_attachments_chat ON chat.attachments (chat_id, created_at DESC);

-- Transactional outbox: the message INSERT AND its `pguard.events.chat.message_sent` row are
-- written in ONE transaction (CLAUDE.md "Cross-tx consistency"); a background relay publishes
-- to NATS so notification consumes (chat-message push). `payload` is a fully-formed
-- EventEnvelope; the relay marks `published_at` only after a successful publish (at-least-once,
-- consumers dedupe on event_id). Mirrors calling.outbox.
CREATE TABLE chat.outbox (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    topic        TEXT        NOT NULL,               -- = EventEnvelope.event_type (NATS subject)
    payload      JSONB       NOT NULL,               -- the serialized EventEnvelope
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ
);

CREATE INDEX idx_chat_outbox_unpublished
    ON chat.outbox (created_at)
    WHERE published_at IS NULL;
