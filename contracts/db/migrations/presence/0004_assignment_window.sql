-- pguard presence-service — record the JOB WINDOW (start/end) on the IDOR read-model so the
-- admin route-playback can be selected BY BOOKING (#141 ดูเส้นทางย้อนหลัง).
--
-- 0002 created `presence.guard_assignments` as the event-derived IDOR gate: it answered "does
-- customer X have an ACTIVE booking with guard Y?" and kept only `updated_at` (the LAST event's
-- `occurred_at`) for last-writer-wins. That is enough for the authz check but NOT enough to
-- replay a booking's GPS track: the admin "play this job's route" view needs the window the job
-- actually ran for — a START anchor (the accept) and an END anchor (the terminal event).
--
-- This migration adds two NULLABLE timestamp columns to the SAME read-model (no new table — the
-- window belongs to the assignment it describes). They are populated by the existing
-- `presence-booking-links` consumer from the booking events it already consumes:
--   * `started_at` ← the `job_accepted` event's `occurred_at` (the job's START anchor). Set ONCE
--     and never advanced backwards by a redelivery (the consumer uses a least-of / first-wins
--     COALESCE so an at-least-once replay can't move the start).
--   * `ended_at`   ← the terminal event's `occurred_at` (`completed`/`cancelled`/`declined`). For
--     a still-active job this stays NULL and the replay reads the window as `started_at … now()`.
--
-- These are DERIVED from the booking events presence already consumes — NO cross-service FK, NO
-- synchronous cross-schema read of booking's tables (CLAUDE.md "Data"). They are NOT a precise
-- "work_started_at"/"work_completed_at" (booking owns those); they are the accept→terminal event
-- window, which is the honest, event-derivable bound for "the guard's points during this job".
--
-- Nullable + no backfill: rows projected before this migration have no window; a by-booking
-- replay of such an old booking returns NotFound for the window (the by-guard+from/to path still
-- works for them). New events populate the columns going forward.

ALTER TABLE presence.guard_assignments
    ADD COLUMN started_at TIMESTAMPTZ,
    ADD COLUMN ended_at   TIMESTAMPTZ;

-- The by-booking replay looks the window up by PRIMARY KEY (`booking_id`), so no extra index is
-- needed for that path. The by-guard+from/to playback is served by the existing
-- `idx_location_history_user_time` btree on `presence.location_history (user_id, recorded_at DESC)`
-- (0001), which already supports the `WHERE user_id = $1 AND recorded_at >= $from AND < $to` scan.
