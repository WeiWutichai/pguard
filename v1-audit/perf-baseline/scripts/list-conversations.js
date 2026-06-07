// B1.3 — List conversations. GET /conversations?role=customer at 20 RPS.
// The N+1-fixed read (chat::repo::list_conversations is ONE query enriching all rows).
// NOTE: chat is NOT wired into the gateway routing table in v2, so this hits the chat service
// DIRECTLY at CHAT_URL (reached by Docker DNS — chat:3010 — when k6 runs on the compose network)
// with the same Bearer the gateway login issued; chat validates the JWT itself (defense-in-depth).
// PREREQ: seed the customer with ~100 conversations (seed-v2.sql).
// Run: k6 run -e TEST_PHONE=08... -e TEST_PASSWORD=... list-conversations.js
import http from 'k6/http';
import { check } from 'k6';
import { CHAT_URL, login, authHeaders } from './_common.js';

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
    'http_req_duration{name:list-conversations}': ['p(99)<2000'], // tag-scoped → clean p99 (excl. setup login)
    http_req_failed: ['rate<0.01'],
  },
};

const ROLE = __ENV.ROLE || 'customer';

export function setup() {
  return { token: login(__ENV.TEST_PHONE || '0820000001', __ENV.TEST_PASSWORD || 'Password123!') };
}

export default function (data) {
  const res = http.get(`${CHAT_URL}/conversations?role=${ROLE}`, {
    headers: authHeaders(data.token),
    tags: { name: 'list-conversations' },
  });
  check(res, {
    'list 200': (r) => r.status === 200,
    'has body': (r) => r.body && r.body.length > 2,
  });
}
