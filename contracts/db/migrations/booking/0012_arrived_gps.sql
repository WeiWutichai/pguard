-- pguard booking-service — capture the guard's GPS at "arrived" (the 120m arrive geofence, G4).
--
-- The proximity gate moved from START (the old 50m fence, migration 0008 columns) to ARRIVAL:
-- `arrive_job` now records WHERE the assigned guard stood when they marked the job arrived, so
-- arrival is the auditable evidence of on-site presence (the same reason hourly check-ins and the
-- start carry GPS — 0004 / 0008). The 120m geofence itself is enforced in the service (pure
-- domain logic against the booking's site `lat`/`lng`), NOT here: the DB only persists the
-- accepted fix. The old `work_started_*` columns (0008) stay — start still persists its fix as
-- audit evidence, it just no longer proximity-gates.
--
-- All three columns are nullable, no default:
--   * legacy address-only bookings (site lat/lng NULL) skip the geofence entirely — their
--     arrivals have no fix to record;
--   * admin-bypass arrivals (support acting on behalf) may carry no GPS;
--   * every booking row that reached `arrived` before this migration has no fix either.
-- NULL therefore means "no verified fix at arrival", never "at (0,0)".
--
-- Types mirror the house GPS style (0004 progress_reports / 0008 start / presence): DOUBLE
-- PRECISION coordinates + REAL accuracy-in-meters.
--
-- Statements are individually idempotent (IF NOT EXISTS) — migrate.sh applies files via psql
-- WITHOUT --single-transaction (statement auto-commit), and a mid-file failure commits earlier
-- statements without a ledger row (see tooling/scripts/migrate.sh).

ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS arrived_lat DOUBLE PRECISION;   -- guard GPS at arrival (NULL = no verified fix)
ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS arrived_lng DOUBLE PRECISION;
ALTER TABLE booking.bookings ADD COLUMN IF NOT EXISTS arrived_accuracy_m REAL;        -- reported fix accuracy in meters (optional)
