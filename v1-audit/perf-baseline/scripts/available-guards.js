// B1.4 — Available guards discovery. GET /booking/available-guards at 30 RPS.
// Exercises the 5-JOIN Haversine radius query.
// PREREQ: seed ~200 guards with online GPS rows inside a 50km radius of the
// query point (see ../README.md §Seeding).
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
    http_req_duration: ['p(99)<2500'], // placeholder — Haversine 5-JOIN; record real p99
    http_req_failed: ['rate<0.01'],
  },
};

const LAT = __ENV.LAT || '13.7563';
const LNG = __ENV.LNG || '100.5018';
const RADIUS = __ENV.RADIUS_KM || '50';
const TOKEN = login(__ENV.TEST_PHONE || '0820000001', __ENV.TEST_PASSWORD || 'Password123!');

export default function () {
  const url = `${BASE_URL}/booking/available-guards?lat=${LAT}&lng=${LNG}&radius_km=${RADIUS}`;
  const res = http.get(url, { headers: authHeaders(TOKEN), tags: { name: 'available-guards' } });
  check(res, { 'discover 200': (r) => r.status === 200 });
}
