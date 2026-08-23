-- pguard notification-service — hourly check-in reminder ledger (N3a).
--
-- A guard working an IN-PROGRESS job must check in (photo + GPS) roughly once an hour. This
-- table is the notification service's own tiny projection of "who is working, and when did they
-- last check in / get reminded" — built PURELY from the booking lifecycle events already flowing
-- over NATS (notification owns NO booking state, per CLAUDE.md "Data"):
--
--   * booking.arrived            → OPEN/refresh the row (guard is (back) at work; reset the clock)
--   * booking.progress_reported  → a check-in landed → stamp last_checkin_at (push the clock forward)
--   * booking.completed          → CLOSE the row (stop reminding)
--   * booking.cancelled          → CLOSE the row (stop reminding)
--
-- The consumer upserts this ledger IN THE SAME transaction that claims the event_id
-- (processed_events), so it is atomic + idempotent under JetStream at-least-once redelivery — a
-- redelivered event is a no-op (the event_id claim loses), never a double reset/wipe.
--
-- A 5-minute scheduler (mirrors the broadcast scheduler) scans this table for DUE rows — open,
-- and ≥ 1h since the later of {last check-in, work start} AND ≥ 1h since the later of {last
-- reminder, work start} — pushes the guard "ถึงเวลาเช็คอิน", and stamps last_reminded_at so the
-- nudge won't re-fire until the next hour.
--
-- Per-service schema ownership: only notification writes here. NO cross-service FK — booking_id /
-- guard_id are bare UUIDs owned by booking/identity (integrity flows via events, not FKs). The
-- index is inline (empty table at creation); a LATER additive index on this populated table must
-- use CREATE INDEX CONCURRENTLY in its own migration (CLAUDE.md "Data").

CREATE TABLE notification.checkin_reminders (
    booking_id        UUID PRIMARY KEY,               -- one open work session per booking (owned by booking; no FK)
    guard_id          UUID        NOT NULL,           -- who to remind (owned by identity; no FK)
    in_progress_since TIMESTAMPTZ NOT NULL DEFAULT now(), -- when the guard (re)arrived → the reminder clock origin
    last_checkin_at   TIMESTAMPTZ,                    -- last hourly check-in (NULL = none since arrival)
    last_reminded_at  TIMESTAMPTZ,                    -- last reminder pushed (NULL = none since arrival)
    closed_at         TIMESTAMPTZ                     -- set on completed/cancelled → stop reminding (NULL = open)
);

-- Scheduler hot path: scan only OPEN rows (the partial index stays tiny — closed work drops out).
CREATE INDEX idx_checkin_reminders_open
    ON notification.checkin_reminders (in_progress_since)
    WHERE closed_at IS NULL;
