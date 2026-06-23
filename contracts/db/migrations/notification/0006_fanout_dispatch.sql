-- pguard notification-service — dispatch fan-out idempotency (booking.requested → all online guards).
--
-- The single-recipient consumer dedupes on processed_events.event_id (one row per event). The
-- new-booking DISPATCH path is different: ONE booking.requested event fans out to MANY guards, so
-- the dedupe granularity must be per-(event, guard) — otherwise a JetStream redelivery of the SAME
-- event_id would re-push every guard. This ledger records each (event_id, recipient) the fan-out
-- has already notified; the consumer claims a row per guard with INSERT ... ON CONFLICT DO NOTHING
-- and only pushes the guards whose claim WON. A redelivery re-claims nothing → no double-notify.
--
-- WHY a separate table (not processed_events): processed_events is keyed by event_id ALONE (it's
-- the global "this event was handled" ledger). The dispatch path intentionally does NOT claim the
-- event_id there — it claims per recipient here — so IF the event is ever redelivered, the retry
-- fills in only the guards not yet recorded and never re-notifies the ones it has. NB: the current
-- consumer (fan_out_dispatch) ACKs even when presence is unreachable or some pushes fail (it does
-- NOT nack), so today this table's job is dedupe-across-redelivery, not a guaranteed fill-in of a
-- dropped push — a missed proactive alert is covered by pull discovery (GET /bookings/open).

CREATE TABLE notification.dispatch_recipients (
    event_id     UUID        NOT NULL,           -- EventEnvelope.event_id (the booking.requested event)
    recipient_id UUID        NOT NULL,           -- the online guard notified for this event
    booking_id   UUID        NOT NULL,           -- carried for audit/debug (which booking this dispatch was for)
    notified_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, recipient_id)         -- per-(event, guard) idempotency claim
);

-- Audit/debug lookups by booking ("who got dispatched this job").
CREATE INDEX idx_dispatch_recipients_booking
    ON notification.dispatch_recipients (booking_id);
