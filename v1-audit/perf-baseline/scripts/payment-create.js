// B1.5 — Payment create. POST /v1/payments at 20 RPS (gateway → payment → service-JWT read of
// booking internal + idempotent charge). Write path + cross-service read contention.
// v2 body = { booking_id, amount, payment_method }. The 100 seeded bookings (seed-v2.sql) are
// status='accepted' (payable) with expected_total = 500×4×1 = 2000, so amount=2000 covers it.
// Charge is idempotent per booking (ON CONFLICT), so cycling the 100 ids re-measures the path
// without double-charging. Booking ids are the deterministic seed UUIDs (no env wiring needed).
// Run: k6 run -e TEST_PHONE=08... -e TEST_PASSWORD=... payment-create.js
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, login, authHeaders } from './_common.js';

export const options = {
  scenarios: {
    pay: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RPS || 20),
      timeUnit: '1s',
      duration: __ENV.DURATION || '1m',
      preAllocatedVUs: 40,
      maxVUs: 120,
    },
  },
  thresholds: {
    'http_req_duration{name:payment-create}': ['p(99)<2000'], // tag-scoped → clean p99 (excl. setup login)
    http_req_failed: ['rate<0.02'],
  },
};

// Deterministic seeded booking pool: 11111111-0000-0000-0000-<hex(i)> for i in 1..100.
const BOOKING_IDS = Array.from({ length: 100 }, (_, k) => {
  const hex = (k + 1).toString(16).padStart(12, '0');
  return `11111111-0000-0000-0000-${hex}`;
});
// `amount` is a Decimal (rust_decimal serde-str) → it MUST be a JSON STRING, not a number.
// == expected_total (base_fee 500 × 4h × 1 guard).
const AMOUNT = String(__ENV.AMOUNT || '2000');

export function setup() {
  return { token: login(__ENV.TEST_PHONE || '0820000001', __ENV.TEST_PASSWORD || 'Password123!') };
}

export default function (data) {
  const bookingId = BOOKING_IDS[Math.floor(Math.random() * BOOKING_IDS.length)];
  const payload = JSON.stringify({
    booking_id: bookingId,
    amount: AMOUNT,
    payment_method: 'promptpay',
  });
  const res = http.post(`${BASE_URL}/v1/payments`, payload, {
    headers: authHeaders(data.token),
    tags: { name: 'payment-create' },
  });
  check(res, { 'pay 2xx': (r) => r.status >= 200 && r.status < 300 });
}
