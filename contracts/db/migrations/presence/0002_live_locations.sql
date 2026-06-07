-- pguard presence-service — live position store + event-derived authz read-model (Phase 2).
--
-- Phase 5 C5.2 established `presence.location_history` (append-only) + its 90-day retention
-- purge (0001). This migration adds the two stores the GPS-over-WebSocket slice needs:
--   1. `guard_locations` — ONE row per guard (UPSERT target): the current position + online
--      flag the admin map / discovery freshness filter read.
--   2. `guard_assignments` — the IDOR read-model that answers "does customer X have an ACTIVE
--      booking with guard Y?" WITHOUT a cross-service FK or a synchronous cross-schema read.
--
-- Per-service schema ownership: ONLY presence-service writes schema `presence` (CLAUDE.md
-- "Data"). All references to a guard/customer are bare UUIDs — NO cross-service FK.

-- ---------------------------------------------------------------------------------------------
-- 1. Current-position store (live map + discovery). One row per guard, upserted on each GPS
--    fix; `is_online` flips true on a fix and false on disconnect/zombie-reap. `recorded_at` is
--    advanced ONLY by a real fix — never by a keep-alive (a guard who lost GPS but holds the
--    socket must not read as fresh).
-- ---------------------------------------------------------------------------------------------
CREATE TABLE presence.guard_locations (
    guard_id    UUID        PRIMARY KEY,
    lat         DOUBLE PRECISION NOT NULL,
    lng         DOUBLE PRECISION NOT NULL,
    -- Device-reported, often absent/garbage on some handsets → nullable, sanitized app-side.
    accuracy    REAL,
    heading     REAL,
    speed       REAL,
    recorded_at TIMESTAMPTZ NOT NULL,
    is_online   BOOLEAN     NOT NULL DEFAULT false
);

-- Live-map / freshness filter: list online guards newest-first. Partial index keeps it tiny
-- (only currently-connected guards) — the bulk admin read filters `is_online = true` and the
-- discovery freshness rule reads `recorded_at` for the live set.
CREATE INDEX idx_guard_locations_online
    ON presence.guard_locations (recorded_at DESC)
    WHERE is_online;

-- ---------------------------------------------------------------------------------------------
-- 2. Event-derived authz read-model (IDOR gate for customer location/history reads).
--    Projected from `pguard.events.booking.*` by presence's durable consumer
--    (`presence-booking-links`): job_accepted → active=true; declined/cancelled/completed →
--    active=false. NO cross-schema read of booking's tables, NO cross-service FK — presence
--    owns this projection. `customer_id`/`guard_id` are nullable so a terminal event seen
--    before its accept can still tombstone the booking (active=false). `updated_at` carries the
--    source event's `occurred_at` so the projection is last-writer-wins (redelivery/reorder
--    safe — at-least-once JetStream delivery never reactivates a finished booking).
-- ---------------------------------------------------------------------------------------------
CREATE TABLE presence.guard_assignments (
    booking_id  UUID        PRIMARY KEY,
    customer_id UUID,
    guard_id    UUID,
    active      BOOLEAN     NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL
);

-- The IDOR lookup: EXISTS active row for (customer_id, guard_id). Partial index over the
-- active set only — the table is small but the read is on the hot per-guard location path.
CREATE INDEX idx_guard_assignments_authz
    ON presence.guard_assignments (customer_id, guard_id)
    WHERE active;
