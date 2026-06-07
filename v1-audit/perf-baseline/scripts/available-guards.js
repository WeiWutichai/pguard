// B1.4 — Available-guards discovery. GET /v1/available-guards at 30 RPS (gateway → booking →
// service-JWT fan-out to profile's approved catalog + rating summaries). Replica-served reads
// (C5.3). NOTE v2 takes NO lat/lng/radius query params (the v1 5-JOIN Haversine is gone —
// discovery returns the approved catalog enriched with rating summaries).
// PREREQ: seed ~200 approved guards (seed-v2.sql).
// Run: k6 run -e TEST_PHONE=08... -e TEST_PASSWORD=... available-guards.js
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, login, authHeaders } from './_common.js';

export const options = {
  scenarios: {
    discover: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RPS || 30),
      timeUnit: '1s',
      duration: __ENV.DURATION || '1m',
      preAllocatedVUs: 60,
      maxVUs: 200,
    },
  },
  thresholds: {
    'http_req_duration{name:available-guards}': ['p(99)<2500'], // tag-scoped → clean p99 (excl. setup login)
    http_req_failed: ['rate<0.01'],
  },
};

// k6 forbids HTTP in the init context — log in ONCE in setup() and pass the token to the VUs.
export function setup() {
  return { token: login(__ENV.TEST_PHONE || '0820000001', __ENV.TEST_PASSWORD || 'Password123!') };
}

export default function (data) {
  const res = http.get(`${BASE_URL}/v1/available-guards`, {
    headers: authHeaders(data.token),
    tags: { name: 'available-guards' },
  });
  check(res, { 'discover 200': (r) => r.status === 200 });
}
