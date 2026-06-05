-- pguard booking-service — Phase 3: customer-reviewed completion.
--
-- A guard no longer marks a job `completed` directly. Instead they request completion
-- (`arrived → pending_completion`); the CUSTOMER reviews and either approves
-- (`pending_completion → completed`, which emits `booking.completed` → payment proration) or
-- rejects (`pending_completion → arrived`, sending the guard back to finish). This mirrors v1
-- (migration 021 `pending_completion`) and gives the customer the final say on completion.
--
-- Postgres requires ALTER TYPE ... ADD VALUE to run OUTSIDE a transaction block; piped to
-- psql (statement auto-commit) this is fine, and the new value is not used until later
-- migrations/queries. Idempotent via IF NOT EXISTS.

ALTER TYPE booking.booking_status ADD VALUE IF NOT EXISTS 'pending_completion' AFTER 'arrived';
