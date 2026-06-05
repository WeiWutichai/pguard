-- pguard presence-service — schema init (GPS location history + retention, Phase 5 C5.2).
--
-- Per-service schema ownership: ONLY presence-service writes to schema `presence`
-- (CLAUDE.md "Data"). `user_id` references a guard by bare UUID — NO cross-service FK.
--
-- PDPA: `location_history` is SENSITIVE real-time GPS (v1-audit/07-pdpa.md §7.1/§7.3).
-- v1 NEVER implemented retention here (unbounded growth of sensitive data — the headline
-- §7.3 gap). This migration creates the store WITH the index the 90-day purge needs.

CREATE SCHEMA IF NOT EXISTS presence;

-- Append-only GPS history for a guard (current position lives in a separate upsert store,
-- added when WS ingestion lands; this slice establishes history + its retention).
CREATE TABLE presence.location_history (
    id          BIGSERIAL   PRIMARY KEY,
    user_id     UUID        NOT NULL,
    latitude    DOUBLE PRECISION NOT NULL,
    longitude   DOUBLE PRECISION NOT NULL,
    -- accuracy in metres, when the device reports it
    accuracy_m  REAL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Retention purge index: the scheduled job runs `DELETE ... WHERE recorded_at < cutoff`.
-- BRIN is ideal here — the table is append-only by time, so physically-adjacent rows share
-- a recorded_at range; BRIN lets the range-delete skip whole block ranges at a fraction of a
-- btree's size on a high-volume sensitive store.
CREATE INDEX idx_location_history_recorded_at
    ON presence.location_history USING BRIN (recorded_at);

-- Per-guard time-range reads (history playback): btree on (user_id, recorded_at desc).
CREATE INDEX idx_location_history_user_time
    ON presence.location_history (user_id, recorded_at DESC);
