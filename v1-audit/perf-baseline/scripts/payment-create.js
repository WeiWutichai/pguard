// B1.5 — Payment create. POST /booking/payments at 20 RPS.
// Captures p99 + DB write contention (payment couples to assignment cost_summary).
// PREREQ: each iteration needs a valid request_id owned by the test customer.
// seed.sql creates these; extract IDs and pass via -e REQUEST_IDS="id1,id2,..." (see README).
// Run: k6 run -e TEST_PHONE=08... -e TEST_PASSWORD=... -e REQUEST_IDS=... payment-create.js
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
    http_req_duration: ['p(99)<2000'], // placeholder — record real p99
    http_req_failed: ['rate<0.02'],
  },
};

const IDS = (__ENV.REQUEST_IDS || '').split(',').filter(Boolean);
const AMOUNT = Number(__ENV.AMOUNT || 1200);
const TOKEN = login(__ENV.TEST_PHONE || '0820000001', __ENV.TEST_PASSWORD || 'Password123!');

export default function () {
  // Pick a request to pay. Without seeded IDs this will 4xx — that still measures
  // the request path but inflates error rate; seed for a clean number.
  const requestId = IDS.length ? IDS[Math.floor(Math.random() * IDS.length)] : 'SEED_ME';
  const payload = JSON.stringify({
    request_id: requestId,
    amount: AMOUNT,
    payment_method: 'promptpay',
  });
  const res = http.post(`${BASE_URL}/booking/payments`, payload, {
    headers: authHeaders(TOKEN),
    tags: { name: 'payment-create' },
  });
  check(res, { 'pay 2xx/4xx (not 5xx)': (r) => r.status < 500 });
}
