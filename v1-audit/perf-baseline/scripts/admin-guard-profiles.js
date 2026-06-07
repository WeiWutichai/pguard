// C5.3 gate — admin guard-profiles list. GET /v1/admin/guard-profiles?approval_status=approved at
// 20 RPS (gateway → profile, replica-served + a §30 access-audit write on the primary). Needs an
// ADMIN token (seed-v2.sql seeds 0800000001). Admin-only (403 otherwise).
// Run: k6 run -e ADMIN_PHONE=08... -e ADMIN_PASSWORD=... admin-guard-profiles.js
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, login, authHeaders } from './_common.js';

export const options = {
  scenarios: {
    adminlist: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RPS || 20),
      timeUnit: '1s',
      duration: __ENV.DURATION || '45s',
      preAllocatedVUs: 40,
      maxVUs: 120,
    },
  },
  thresholds: {
    'http_req_duration{name:admin-guard-profiles}': ['p(99)<2500'],
    http_req_failed: ['rate<0.01'],
  },
};

const STATUS = __ENV.STATUS || 'approved';

export function setup() {
  return { token: login(__ENV.ADMIN_PHONE || '0800000001', __ENV.ADMIN_PASSWORD || 'Password123!') };
}

export default function (data) {
  const res = http.get(`${BASE_URL}/v1/admin/guard-profiles?approval_status=${STATUS}`, {
    headers: authHeaders(data.token),
    tags: { name: 'admin-guard-profiles' },
  });
  check(res, { 'list 200': (r) => r.status === 200 });
}
