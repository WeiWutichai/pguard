-- pguard booking-service — capture the guard's GPS at "start work" (the 50m geofence).
--
-- `start_job` now records WHERE the assigned guard stood when they pressed start, so the
-- start is auditable evidence of on-site presence (the same reason hourly check-ins carry
-- GPS — 0004). The 50m geofence itself is enforced in the service (pure domain logic
-- against the booking's site `lat`/`lng`), NOT here: the DB only persists the accepted fix.
--
-- All three columns are nullable, no default:
--   * legacy address-only bookings (site lat/lng NULL) skip the geofence entirely — their
--     starts have no fix to record;
--   * admin-bypass starts (support acting on behalf) may carry no GPS;
--   * every booking row started before this migration has no fix either.
-- NULL therefore means "no verified fix at start", never "at (0,0)".
--
-- Types mirror the house GPS style (0004 progress_reports / presence): DOUBLE PRECISION
-- coordinates + REAL accuracy-in-meters.
--
-- Statements are individually idempotent (IF NOT EXISTS) — migrate.sh applies files via
-- psql WITHOUT --single-transaction (statement auto-commit), and a mid-file failure
-- commits earlier statements without a ledger row (see tooling/scripts/migrate.sh).

ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS work_started_lat DOUBLE PRECISION;  -- guard GPS at start (NULL = no verified fix)
ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS work_started_lng DOUBLE PRECISION;
ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS work_started_accuracy_m REAL;       -- reported fix accuracy in meters (optional)
