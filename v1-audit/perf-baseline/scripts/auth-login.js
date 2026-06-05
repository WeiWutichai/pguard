// B1.6 — Auth login. POST /auth/login/mobile at 10 RPS.
// Captures Argon2 verify p99 (CPU-bound — drives service sizing & pool config).
// No seeding beyond one valid credential; every iteration re-verifies the hash.
// Run: k6 run -e TEST_PHONE=08... -e TEST_PASSWORD=... auth-login.js
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL } from './_common.js';

export const options = {
  scenarios: {
    login: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RPS || 10),
      timeUnit: '1s',
      duration: __ENV.DURATION || '1m',
      preAllocatedVUs: 30,
      maxVUs: 100,
    },
  },
  thresholds: {
    http_req_duration: ['p(99)<1500'], // Argon2 is intentionally slow; record real p99
    http_req_failed: ['rate<0.01'],
  },
};

const PHONE = __ENV.TEST_PHONE || '0820000001';
const PASSWORD = __ENV.TEST_PASSWORD || 'Password123!';

export default function () {
  const res = http.post(
    `${BASE_URL}/auth/login/mobile`,
    JSON.stringify({ phone: PHONE, password: PASSWORD }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'auth-login' } }
  );
  check(res, { 'login 200': (r) => r.status === 200 });
}
