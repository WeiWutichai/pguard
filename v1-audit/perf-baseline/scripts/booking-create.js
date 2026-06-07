// B1.2 — Booking create. POST /v1/bookings at 50 RPS (gateway → booking). Write path.
// v2 body = CreateBookingRequest { address, scheduled_at (RFC3339), hours, guard_count?, tip? }
// — base_fee is server-set (no lat/lng/description/urgency like v1).
// Run: k6 run -e TEST_PHONE=08... -e TEST_PASSWORD=... booking-create.js
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, login, authHeaders } from './_common.js';

export const options = {
  scenarios: {
    create: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RPS || 50),
      timeUnit: '1s',
      duration: __ENV.DURATION || '2m',
      preAllocatedVUs: 100,
      maxVUs: 300,
    },
  },
  thresholds: {
    'http_req_duration{name:booking-create}': ['p(99)<1500'], // tag-scoped → clean p99 (excl. setup login)
    http_req_failed: ['rate<0.01'],
  },
};

export function setup() {
  return { token: login(__ENV.TEST_PHONE || '0820000001', __ENV.TEST_PASSWORD || 'Password123!') };
}

export default function (data) {
  const payload = JSON.stringify({
    address: '123 Sukhumvit Rd, Bangkok',
    scheduled_at: new Date(Date.now() + 86400000).toISOString(), // +1 day
    hours: 4,
    guard_count: 1,
    // `tip` is a Decimal (rust_decimal serde-str) → JSON STRING, not a number. Omit ⇒ defaults 0.
  });
  const res = http.post(`${BASE_URL}/v1/bookings`, payload, {
    headers: authHeaders(data.token),
    tags: { name: 'booking-create' },
  });
  check(res, { 'created 2xx': (r) => r.status >= 200 && r.status < 300 });
}
