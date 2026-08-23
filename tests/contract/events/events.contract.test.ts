// Event-contract verification — trigger REAL events on the live stack, read the emitted
// EventEnvelope from the producing service's transactional outbox, and validate it against the
// AsyncAPI schema in contracts/asyncapi/events.yaml.
//
// We read the outbox row directly (rather than subscribing to NATS) because:
//  - the envelope is written to the outbox in the SAME tx as the business change, so it exists the
//    moment the API call returns 200 — no polling, no flakiness;
//  - NATS messages are HMAC-signed (verify-fail-closed), so a naive subscriber would need the
//    signing secret; the outbox `payload` column is the unsigned envelope JSON.
//
// The outbox `payload` JSONB holds the WHOLE envelope { event_id, event_type, occurred_at,
// correlation_id, traceparent?, payload }; business fields live under .payload.
import { describe, expect, it } from "vitest";

import { ADMIN, CUSTOMER, GUARD } from "../src/accounts.js";
import {
  createPendingGuard,
  insertArrivedBooking,
  readOutboxEnvelope,
} from "../src/db.js";
import { accessToken, bearer, gatewayUrl, http, tinyJpeg } from "../src/http.js";
import { assertEventMatchesSchema, assertResponseMatchesSpec } from "../src/validate.js";

// Future scheduled_at — create rejects past/now (SCHEDULED_IN_PAST); tomorrow never rots.
const futureScheduledAt = new Date(Date.now() + 86_400_000).toISOString();

describe("event contracts (real emissions → outbox → AsyncAPI schema)", () => {
  it("user.approved: admin approval emits a contract-shaped envelope to profile.outbox", async () => {
    const guard = createPendingGuard();
    const adminToken = await accessToken(ADMIN);

    const approve = await http(gatewayUrl(`/admin/guard-profiles/${guard.userId}/approve`), {
      method: "POST",
      headers: bearer(adminToken),
    });
    expect(approve.status, JSON.stringify(approve.body)).toBe(200);

    const envelope = readOutboxEnvelope(
      "profile.outbox",
      "pguard.events.user.approved",
      "user_id",
      guard.userId,
    );
    expect(envelope, "expected a user.approved row in profile.outbox").toBeTruthy();
    await assertEventMatchesSchema("EnvelopeOf_UserApproved", envelope);
    expect((envelope as { payload: { role: string } }).payload.role).toBe("guard");
  });

  it("booking.job_accepted: a guard accepting a booking emits a contract-shaped envelope", async () => {
    const customerToken = await accessToken(CUSTOMER);
    const guardToken = await accessToken(GUARD);

    // Customer creates an open (requested) booking.
    const created = await http(gatewayUrl("/bookings"), {
      method: "POST",
      headers: { ...bearer(customerToken), "content-type": "application/json" },
      body: JSON.stringify({
        address: "1 JobAccepted Rd, Bangkok",
        scheduled_at: futureScheduledAt,
        hours: 4,
      }),
    });
    expect(created.status).toBe(200);
    const bookingId = (created.body as { data: { id: string } }).data.id;

    // The test guard accepts it (positive role path) → emits job_accepted.
    const accepted = await http(gatewayUrl(`/bookings/${bookingId}/accept`), {
      method: "POST",
      headers: bearer(guardToken),
    });
    expect(accepted.status, JSON.stringify(accepted.body)).toBe(200);
    await assertResponseMatchesSpec("booking", "post", "/bookings/{id}/accept", accepted);
    expect((accepted.body as { data: { status: string } }).data.status).toBe("accepted");

    const envelope = readOutboxEnvelope(
      "booking.outbox",
      "pguard.events.booking.job_accepted",
      "booking_id",
      bookingId,
    );
    expect(envelope, "expected a job_accepted row in booking.outbox").toBeTruthy();
    await assertEventMatchesSchema("EnvelopeOf_JobAccepted", envelope);
    const payload = (envelope as { payload: { guard_id: string; customer_id: string } }).payload;
    expect(payload.guard_id).toBe(GUARD.userId);
    expect(payload.customer_id).toBe(CUSTOMER.userId);
  });

  it("booking.progress_reported: a check-in emits a contract-shaped envelope (and the HTTP 200 is contract-shaped)", async () => {
    // Fixture: a booking already arrived + work-started (the exact check-in precondition).
    const bookingId = insertArrivedBooking(CUSTOMER.userId, GUARD.userId);
    const guardToken = await accessToken(GUARD);

    const fd = new FormData();
    fd.append("hour_number", "1");
    fd.append("photo", new Blob([tinyJpeg()], { type: "image/jpeg" }), "checkin.jpg");

    const res = await http(gatewayUrl(`/bookings/${bookingId}/progress-reports`), {
      method: "POST",
      headers: bearer(guardToken), // no content-type — fetch sets the multipart boundary
      body: fd,
    });
    expect(res.status, JSON.stringify(res.body)).toBe(200);
    await assertResponseMatchesSpec("booking", "post", "/bookings/{id}/progress-reports", res);

    const envelope = readOutboxEnvelope(
      "booking.outbox",
      "pguard.events.booking.progress_reported",
      "booking_id",
      bookingId,
    );
    expect(envelope, "expected a progress_reported row in booking.outbox").toBeTruthy();
    await assertEventMatchesSchema("EnvelopeOf_ProgressReported", envelope);
    expect((envelope as { payload: { hour_number: number } }).payload.hour_number).toBe(1);

    // Duplicate hour → 409 with the machine-readable sub-code `DUPLICATE_CHECK_IN` (PR #31 merged).
    // The 409 response schema is a free-form ErrorBody, so this exact-code assertion is the ONLY
    // thing pinning the sub-code split — keep it exact (not a loose set).
    const dup = await http(gatewayUrl(`/bookings/${bookingId}/progress-reports`), {
      method: "POST",
      headers: bearer(guardToken),
      body: (() => {
        const f = new FormData();
        f.append("hour_number", "1");
        f.append("photo", new Blob([tinyJpeg()], { type: "image/jpeg" }), "dup.jpg");
        return f;
      })(),
    });
    expect(dup.status).toBe(409);
    await assertResponseMatchesSpec("booking", "post", "/bookings/{id}/progress-reports", dup);
    const code = (dup.body as { error: { code: string } }).error.code;
    expect(code).toBe("DUPLICATE_CHECK_IN");
  });
});
