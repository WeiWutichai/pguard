// B1.3 — List conversations. GET /chat/conversations?role=customer at 20 RPS for 1 min.
// Exercises the known N+1 (chat::service::list_conversations enriches each row).
// PREREQ: seed the login user with ~100 conversations (see ../README.md §Seeding).
// Run: k6 run -e TEST_PHONE=08... -e TEST_PASSWORD=... list-conversations.js
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, login, authHeaders } from './_common.js';

export const options = {
  scenarios: {
    list: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RPS || 20),
      timeUnit: '1s',
      duration: __ENV.DURATION || '1m',
      preAllocatedVUs: 50,
      maxVUs: 150,
    },
  },
  thresholds: {
    http_req_duration: ['p(99)<2000'], // placeholder — N+1 expected to be slow; record real p99
    http_req_failed: ['rate<0.01'],
  },
};

const ROLE = __ENV.ROLE || 'customer';
const TOKEN = login(__ENV.TEST_PHONE || '0820000001', __ENV.TEST_PASSWORD || 'Password123!');

export default function () {
  const res = http.get(`${BASE_URL}/chat/conversations?role=${ROLE}`, {
    headers: authHeaders(TOKEN),
    tags: { name: 'list-conversations' },
  });
  check(res, {
    'list 200': (r) => r.status === 200,
    'has body': (r) => r.body && r.body.length > 2,
  });
}
