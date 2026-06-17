-- pguard profile-service — event-derived IDOR read-model for customer-readable guard reads.
--
-- The customer live-tracking map shows the ASSIGNED guard's mini-profile (name + experience).
-- That read (`GET /guards/{id}/public`) must be gated: a customer may see a guard's name ONLY
-- while they have an ACTIVE booking with that guard — never an arbitrary guard. profile owns no
-- booking data, so (exactly like presence's `guard_assignments`, migration `presence/0002`) it
-- derives the answer from `pguard.events.booking.*` via its own durable consumer
-- (`profile-booking-links`): job_accepted → active=true; declined/cancelled/completed →
-- active=false. NO cross-service FK, NO cross-schema read of booking's tables — profile owns
-- this projection in its OWN schema (CLAUDE.md "Data": only profile writes schema `profile`).
--
-- `customer_id`/`guard_id` are nullable so a terminal event seen before its accept can still
-- tombstone the booking (active=false); the consumer COALESCEs the known ids from the accept.
-- `updated_at` carries the source event's `occurred_at` so the projection is last-writer-wins
-- (at-least-once JetStream redelivery/reorder never reactivates a finished booking).

CREATE TABLE profile.guard_assignments (
    booking_id  UUID        PRIMARY KEY,
    customer_id UUID,
    guard_id    UUID,
    active      BOOLEAN     NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL
);

-- The IDOR lookup: EXISTS active row for (customer_id, guard_id). Partial index over the active
-- set only (the table is small, but the read is on the per-guard public-profile path).
CREATE INDEX idx_profile_guard_assignments_authz
    ON profile.guard_assignments (customer_id, guard_id)
    WHERE active;
