// B1.2 — Booking create. POST /booking/requests at 50 RPS for 2 min.
// Captures p50/p95/p99 latency + error rate.
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
    http_req_duration: ['p(99)<1500'], // baseline gate placeholder — replace with measured +20%
    http_req_failed: ['rate<0.01'],
  },
};

const TOKEN = login(__ENV.TEST_PHONE || '0820000001', __ENV.TEST_PASSWORD || 'Password123!');

export default function () {
  // Matches booking::models::CreateRequestDto (verified against v1).
  const payload = JSON.stringify({
    location_lat: 13.7563,
    location_lng: 100.5018,
    address: '123 Sukhumvit Rd, Bangkok',
    description: 'k6 baseline',
    urgency: 'medium',
    booked_hours: 4,
    guard_count: 1,
  });
  const res = http.post(`${BASE_URL}/booking/requests`, payload, {
    headers: authHeaders(TOKEN),
    tags: { name: 'booking-create' },
  });
  check(res, { 'created 2xx': (r) => r.status >= 200 && r.status < 300 });
}
