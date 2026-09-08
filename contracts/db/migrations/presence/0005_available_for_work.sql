-- pguard presence-service — separate the guard's "พร้อมรับงาน" INTENT from "a GPS socket exists",
-- and give a dead session a way to expire itself.
--
-- THE BUG (QA 08/09/2569): "Guard ที่ยังไม่ได้เปิด Online Status ต้องไม่แสดงอยู่ในหน้าเลือก Guard".
-- There was NO server-side record of that toggle at all. `guard_locations.is_online` — the ONLY
-- signal booking's discovery filtered on — is set true by the ARRIVAL OF A GPS FIX on the tracking
-- WebSocket (0002), and the mobile app opens that socket whenever `online || jobIds.isNotEmpty`
-- (`tracking_controller.dart`). So a guard sitting on an active-job screen with the toggle OFF
-- streamed GPS, was flagged `is_online = true`, and was offered to customers. The toggle was pure
-- client state that never left the handset.
--
-- 1. `available_for_work` — the guard's DECLARED intent, carried on the WS session itself
--    (`{"type":"availability"}` frame) and re-asserted by every fix that session upserts. It is
--    SESSION-SCOPED on purpose: `set_offline` clears it on any disconnect, so "no live session"
--    can never mean "available". Defaulting to FALSE is the fail-safe direction — a guard is
--    offerable only after explicitly saying so, which is exactly what the requirement asks.
--    (Consequence, deliberate: after this migration nobody is offerable until their app declares
--    availability, so this deploy is coupled to the matching mobile build.)
--
-- 2. `last_seen_at` — SESSION liveness, distinct from `recorded_at` (GPS freshness). It advances on
--    ANY inbound frame including Pong/heartbeat; `recorded_at` still advances only on a real fix
--    (0002's rule, kept: a guard who lost GPS but holds the socket must not read as fresh). This
--    is what lets a row EXPIRE: `set_offline` runs in the WS task, so a presence crash/SIGKILL/
--    redeploy leaves every connected guard's row stuck at `is_online = true` forever — the exact
--    "the app says offline but the customer still sees me" report. A liveness window on
--    `last_seen_at` self-heals that within ~2 minutes with no boot-time reset (which would be
--    wrong under multiple replicas: a restarting replica would evict the other's live sessions).
--    Gating on `last_seen_at` does NOT reintroduce bug B (the movement-gated uplink letting a
--    STATIONARY online guard's `recorded_at` age out of discovery) precisely because keep-alives
--    advance it and fixes are not required.
--
-- Both columns are additive: a NOT NULL BOOLEAN with a constant DEFAULT and a nullable TIMESTAMPTZ
-- are metadata-only in PG 11+ (no table rewrite). Idempotent (`IF NOT EXISTS`) — re-runnable.

ALTER TABLE presence.guard_locations
    ADD COLUMN IF NOT EXISTS available_for_work BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE presence.guard_locations
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

-- Backfill pre-existing rows so liveness reads from the last thing we actually saw rather than
-- NULL. Cosmetic only — `available_for_work` is false on every backfilled row, so none of them is
-- offerable until its guard's app declares availability on a live session.
UPDATE presence.guard_locations
   SET last_seen_at = recorded_at
 WHERE last_seen_at IS NULL;

-- The discovery OFFERABLE set (`repo::online_guard_locations`): connected AND declared available.
-- CONCURRENTLY (CLAUDE.md "Data") — additive index on a populated table; runs outside a
-- transaction, which the migrator honours (each statement autocommits).
--
-- `last_seen_at` is deliberately NOT part of the key: it is rewritten every ~30 s per live session,
-- and an indexed column cannot take the HOT-update path. The partial predicate already narrows the
-- scan to the handful of offerable guards, so the liveness bound is a cheap heap filter on top.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_guard_locations_offerable
    ON presence.guard_locations (guard_id)
    WHERE is_online AND available_for_work;
