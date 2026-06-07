// B1.6 — Auth login. POST /v1/auth/login at 10 RPS (gateway → identity).
// Captures Argon2 verify p99 (CPU-bound — drives identity-service sizing & pool config).
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
    'http_req_duration{name:auth-login}': ['p(99)<1500'], // tag-scoped → clean per-endpoint p99
    http_req_failed: ['rate<0.01'],
  },
};

const PHONE = __ENV.TEST_PHONE || '0820000001';
const PASSWORD = __ENV.TEST_PASSWORD || 'Password123!';

export default function () {
  const res = http.post(
    `${BASE_URL}/v1/auth/login`,
    JSON.stringify({ identifier: PHONE, password: PASSWORD }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'auth-login' } }
  );
  check(res, { 'login 200': (r) => r.status === 200 });
}
