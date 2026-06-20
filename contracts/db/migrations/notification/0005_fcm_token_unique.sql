-- pguard notification-service — a device token belongs to AT MOST one user.
--
-- BUG (deep-review MEDIUM): fcm_tokens had only UNIQUE(user_id, token), so the SAME device
-- token could be stored under MULTIPLE user_ids. When FCM rotates/reassigns a token to a new
-- login, the old rows linger and keep delivering the previous user's notifications to the new
-- user's device (cross-user leak). FIX: enforce UNIQUE(token) and re-point on re-register
-- (register_token now upserts ON CONFLICT (token)); send_one prunes tokens FCM reports dead.
--
-- This migration is the only one in this folder that runs OUTSIDE a transaction: CREATE INDEX
-- CONCURRENTLY (CLAUDE.md "Data": new indexes on populated tables) cannot run in a tx block.

-- 1) De-duplicate any pre-existing rows that share a token, keeping the most recently updated
--    (the live login). Done in a tx so the table is consistent before the unique index builds.
BEGIN;
DELETE FROM notification.fcm_tokens a
USING notification.fcm_tokens b
WHERE a.token = b.token
  AND (a.updated_at, a.id) < (b.updated_at, b.id);

-- The new UNIQUE(token) subsumes UNIQUE(user_id, token); drop the redundant pair constraint.
ALTER TABLE notification.fcm_tokens
    DROP CONSTRAINT IF EXISTS fcm_tokens_user_id_token_key;
COMMIT;

-- 2) Build the unique index concurrently (no long write lock on a populated table), then attach
--    it as the UNIQUE(token) constraint that register_token's ON CONFLICT (token) targets.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_fcm_tokens_token
    ON notification.fcm_tokens (token);

ALTER TABLE notification.fcm_tokens
    ADD CONSTRAINT fcm_tokens_token_key UNIQUE USING INDEX idx_fcm_tokens_token;
