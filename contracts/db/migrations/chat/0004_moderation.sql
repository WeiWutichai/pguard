-- pguard chat-service — admin MODERATION (Phase D: #136/#137).
--
-- Phase C added the admin READ surface (GET /admin/conversations + the enriched message audit).
-- This migration adds the WRITE/moderation model the design called for but had no v2 endpoint
-- ("การกำกับ ตั้งค่าสถานะ/ลบข้อความ/บล็อก/เก็บถาวร ยังไม่มี endpoint"):
--
--   (1) MESSAGE REDACTION (soft-delete) — additive columns on `chat.messages`. Content is NEVER
--       hard-deleted (audit/PDPA defensibility); a redacted row is kept but its `content` is
--       SUPPRESSED on every read path and shown as "removed". `redacted_by`/`redacted_at`/
--       `redacted_reason` record who/when/why.
--
--   (2) CONVERSATION MODERATION STATUS / ARCHIVE — `moderation_status` ('active' | 'archived')
--       + `archived_by`/`archived_at` on `chat.conversations`. This is DISTINCT from the existing
--       `request_status` (booking lifecycle, drives the read-only-on-completion gate): an admin can
--       archive an OPEN booking's thread without touching the booking, and an active booking's
--       thread is never auto-archived. Archiving freezes writes (a second read-only gate, admin-set).
--
--   (3) CHAT-LEVEL USER BLOCK — `chat.user_blocks`: a per-user chat ban flag (bare `user_id`, no
--       cross-svc FK — identity owns users). A blocked user cannot SEND in any conversation
--       (enforced in `repo::send_message`, the single write path). Block/unblock are IDEMPOTENT:
--       a row with `lifted_at IS NULL` is an ACTIVE block; unblock stamps `lifted_at` (kept for
--       audit, never row-deleted). A partial unique index guarantees at most ONE active block per
--       user so a repeated block is a no-op (ON CONFLICT DO NOTHING).
--
--   (4) AUDIT LEDGER — `chat.moderation_actions`: an append-only who/when/what/why record for every
--       moderation write (redact_message | archive_conversation | unarchive_conversation |
--       block_user | unblock_user), so the actions are defensible after the fact. `actor_id` is the
--       admin's user_id; `target_id` is the affected message/conversation/user; `reason` is optional.
--
-- Per-service schema ownership: ONLY chat-service writes schema `chat` (CLAUDE.md "Data"). No
-- cross-service foreign keys — `redacted_by`/`archived_by`/`actor_id`/`user_id`/`blocked_by` are
-- bare UUIDs owned by identity. All statements are additive + idempotent (IF NOT EXISTS / additive
-- columns), safe to re-run. CREATE INDEX CONCURRENTLY (CLAUDE.md "Data") on the existing-and-
-- possibly-populated `chat.messages` so the redaction read filter is fast without locking writes;
-- the CONCURRENTLY statements run OUTSIDE a transaction (the migrator applies each file in
-- autocommit; this file has no BEGIN/COMMIT).

-- ── (1) message redaction (soft-delete) ─────────────────────────────────────────────────────
-- Additive, nullable columns — instant on an existing table (no rewrite, no default backfill). A
-- non-null `redacted_at` marks the message as removed; the read path suppresses `content`.
ALTER TABLE chat.messages
    ADD COLUMN IF NOT EXISTS redacted_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS redacted_by     UUID,          -- admin user_id (no cross-svc FK)
    ADD COLUMN IF NOT EXISTS redacted_reason TEXT;

-- ── (2) conversation moderation status / archive ───────────────────────────────────────────
-- `moderation_status` defaults to 'active'; only an admin archive flips it to 'archived'. The
-- DEFAULT applies to NEW rows and is filled for existing rows by the additive ADD COLUMN (a
-- constant default → fast, no table rewrite on PG11+). CHECK constrains the small enum in-place
-- (no schema-qualified enum type needed — mirrors `request_status` being a bare VARCHAR).
ALTER TABLE chat.conversations
    ADD COLUMN IF NOT EXISTS moderation_status VARCHAR(20) NOT NULL DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS archived_at       TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS archived_by       UUID;        -- admin user_id (no cross-svc FK)

-- Constrain the moderation_status enum. Added as a separate, NOT-VALID-then-VALIDATE-free statement
-- via IF NOT EXISTS guard so a re-run is a no-op. (DO block: ADD CONSTRAINT has no IF NOT EXISTS.)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_chat_conversations_moderation_status'
    ) THEN
        ALTER TABLE chat.conversations
            ADD CONSTRAINT chk_chat_conversations_moderation_status
            CHECK (moderation_status IN ('active', 'archived'));
    END IF;
END $$;

-- ── (3) chat-level user block ──────────────────────────────────────────────────────────────
-- A per-user chat ban. At most ONE active block per user (lifted_at IS NULL); a lifted block is
-- retained for audit. The send path consults this (a blocked user's send is rejected).
CREATE TABLE IF NOT EXISTS chat.user_blocks (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL,              -- the blocked user (owned by identity; no FK)
    blocked_by UUID        NOT NULL,              -- admin user_id who blocked
    reason     TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    lifted_at  TIMESTAMPTZ,                       -- non-null ⇒ block lifted (unblocked); audit-kept
    lifted_by  UUID                               -- admin user_id who unblocked
);

-- At most ONE active (un-lifted) block per user → block is idempotent (ON CONFLICT DO NOTHING) and
-- the send-path lookup ("is this user actively blocked?") is a single indexed probe.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_chat_user_blocks_active
    ON chat.user_blocks (user_id)
    WHERE lifted_at IS NULL;

-- ── (4) moderation audit ledger ────────────────────────────────────────────────────────────
-- Append-only. Every admin moderation write inserts one row here in the SAME transaction as the
-- effect, so the action is defensible (who/when/what/why). target_kind disambiguates target_id.
CREATE TABLE IF NOT EXISTS chat.moderation_actions (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id    UUID        NOT NULL,             -- admin user_id who performed the action
    action      VARCHAR(40) NOT NULL,             -- redact_message | archive_conversation | …
    target_kind VARCHAR(20) NOT NULL,             -- 'message' | 'conversation' | 'user'
    target_id   UUID        NOT NULL,             -- the affected message/conversation/user id
    reason      TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Audit lookups by target (e.g. "show this conversation's moderation history"), newest first.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chat_moderation_actions_target
    ON chat.moderation_actions (target_kind, target_id, created_at DESC);

-- The read path filters redacted messages cheaply (it still returns the row, but suppresses
-- content); a partial index keeps the "is redacted" predicate index-only where it's used.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chat_messages_redacted
    ON chat.messages (conversation_id)
    WHERE redacted_at IS NOT NULL;
