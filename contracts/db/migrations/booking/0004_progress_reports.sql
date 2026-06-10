-- pguard booking-service — progress reports (guard hourly check-in) + open-job discovery.
--
-- (1) `booking.progress_reports`: one row per (booking, hour) check-in — photo lives in
--     S3/MinIO, only the object KEY is stored here (CLAUDE.md "Data": binary blobs stay
--     in S3). `booking_id` FK is WITHIN this service's own schema (allowed); `guard_id`
--     is a bare UUID owned by identity (no cross-service FK).
-- (2) `booking.bookings` gains nullable `lat`/`lng` (DOUBLE PRECISION — house style for
--     coordinates, presence/0002) so open-job discovery can filter by radius. Nullable:
--     pre-existing rows have no coordinates and the create API only OPTIONALLY accepts
--     them; bookings without coordinates simply never match a radius filter.
--
-- Statements are individually idempotent (IF NOT EXISTS) — migrate.sh applies files via
-- psql WITHOUT --single-transaction (statement auto-commit), and a mid-file failure
-- commits earlier statements without a ledger row (see tooling/scripts/migrate.sh).
-- Indexes are plain CREATE INDEX (inline-on-empty-table house style; these tables are
-- pre-production — CONCURRENTLY is reserved for later additive indexes on populated tables).

ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;

CREATE TABLE IF NOT EXISTS booking.progress_reports (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id  UUID             NOT NULL REFERENCES booking.bookings (id) ON DELETE CASCADE,
    guard_id    UUID             NOT NULL,            -- the reporting (assigned) guard; identity-owned (no FK)
    hour_number INT              NOT NULL,
    photo_key   TEXT             NOT NULL,            -- S3 object key (never a blob, never a stale signed URL)
    lat         DOUBLE PRECISION,                     -- GPS stamped at photo-capture time (optional — guard may be offline)
    lng         DOUBLE PRECISION,
    accuracy_m  REAL,                                 -- GPS accuracy in meters (optional; mirrors presence)
    note        TEXT,
    created_at  TIMESTAMPTZ      NOT NULL DEFAULT now(),
    CONSTRAINT chk_progress_reports_hour CHECK (hour_number BETWEEN 1 AND 168)
);

-- One check-in per (booking, hour): the duplicate-hour 409 is enforced here, so a guard's
-- retry can never double-report an hour (idempotent client retry). Doubles as the
-- (booking_id, hour_number) read index for listing a booking's reports in hour order.
CREATE UNIQUE INDEX IF NOT EXISTS uq_progress_reports_booking_hour
    ON booking.progress_reports (booking_id, hour_number);

-- Open-job discovery hot path: `status = 'requested' AND guard_id IS NULL`, newest first.
CREATE INDEX IF NOT EXISTS idx_bookings_open
    ON booking.bookings (created_at DESC)
    WHERE status = 'requested' AND guard_id IS NULL;
