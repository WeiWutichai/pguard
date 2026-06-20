-- pguard chat-service — one conversation per booking (idempotency hardening).
--
-- `chat.conversations` previously had only a PLAIN index on `request_id`, so a repeated
-- create-conversation (e.g. the mobile client POSTing again once the guard comes online, or a
-- retry) accumulated DUPLICATE conversations for the same booking. This makes `request_id`
-- UNIQUE so the create path is GET-OR-CREATE: the `ON CONFLICT (request_id) DO NOTHING` insert
-- returns the EXISTING conversation instead of a duplicate. It also hardens the authz fix —
-- one canonical conversation per booking, whose identity is booking-authoritative.
--
-- Per-service schema ownership: only chat-service writes schema `chat` (CLAUDE.md "Data").
-- The table may be populated in a running environment, so this additive index uses
-- CREATE [UNIQUE] INDEX CONCURRENTLY (CLAUDE.md "Data") — runs outside a transaction (the
-- migrator applies each file in autocommit; this file has no BEGIN/COMMIT).
--
-- NOTE: if pre-existing duplicate request_id rows exist, the CONCURRENTLY build will fail and
-- the index lands INVALID; de-dup first (keep the oldest conversation per request_id) then
-- REINDEX. A fresh v2 environment has none, so the normal path is a clean build.

-- The unique index also serves every existing `request_id` lookup (the status-push UPDATE +
-- the by-request reads), so the old plain index is now redundant — drop it to avoid a
-- duplicate index on the same column.
DROP INDEX CONCURRENTLY IF EXISTS chat.idx_chat_conversations_request;

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_chat_conversations_request
    ON chat.conversations (request_id);
