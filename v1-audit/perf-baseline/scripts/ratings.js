// C5.3 gate — public ratings read. GET /guards/{id}/ratings at 30 RPS (replica-served).
// Public endpoint (filters is_visible). rating is NOT gateway-routed in v2, so this hits the
// rating service DIRECTLY (RATING_URL). PREREQ: seed reviews for the guard (seed-v2.sql seeds
// the first 50 guards with 3 visible reviews each).
// Run: k6 run -e GUARD_ID=... ratings.js
import http from 'k6/http';
import { check } from 'k6';
import { RATING_URL } from './_common.js';

export const options = {
  scenarios: {
    ratings: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RPS || 30),
      timeUnit: '1s',
      duration: __ENV.DURATION || '1m',
      preAllocatedVUs: 60,
      maxVUs: 200,
    },
  },
  thresholds: {
    'http_req_duration{name:ratings}': ['p(99)<2500'], // tag-scoped → clean per-endpoint p99
    http_req_failed: ['rate<0.01'],
  },
};

const GUARD_ID = __ENV.GUARD_ID || '99999999-0000-0000-0000-000000000001';

export default function () {
  const res = http.get(`${RATING_URL}/guards/${GUARD_ID}/ratings`, {
    tags: { name: 'ratings' },
  });
  check(res, { 'ratings 200': (r) => r.status === 200 });
}
