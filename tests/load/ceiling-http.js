// Ceiling finder (HTTP) — one endpoint, one fixed arrival rate, short hold.
// The reproduce harness (run-ceiling.sh) calls this repeatedly at INCREASING -e RPS and reads
// the one-line CEILING_RESULT from handleSummary to find the knee (where p99 explodes or
// http_req_failed climbs). Constant-arrival-rate (open model) so a slow server BACKS UP the
// arrival queue instead of throttling the offered load — that's what exposes the true ceiling.
//
// Reuses the baseline harness (NOT copied): login()/BASE_URL come from the perf-baseline
// _common.js via a relative import; run k6 with the repo root mounted so the path resolves.
//
//   -e ENDPOINT=login|discovery|booking   (default discovery)
//   -e RPS=<n>  -e DURATION=20s
import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, login, authHeaders } from '../../v1-audit/perf-baseline/scripts/_common.js';

const ENDPOINT = __ENV.ENDPOINT || 'discovery';
const RPS = Number(__ENV.RPS || 50);
const DURATION = __ENV.DURATION || '20s';

// TARGET=gateway (default) measures the EDGE path (subject to the gateway per-IP rate limit —
// the first thing that breaks under single-source load). TARGET=direct hits the owning service
// on the compose network with the SAME Bearer, BYPASSING the edge rate limit, to find the true
// BACKEND ceiling (Argon2 CPU / DB pool). Backends re-validate the Bearer (AuthUser), so direct
// works; they serve BARE paths (no /v1 — the gateway strips it).
const TARGET = __ENV.TARGET || 'gateway';
const DIRECT = TARGET === 'direct';
const IDENTITY_URL = __ENV.IDENTITY_URL || 'http://identity:3001';
const BOOKING_URL = __ENV.BOOKING_URL || 'http://booking:3005';

// preAllocatedVUs must be generous enough that VU starvation (not the server) never caps the
// offered rate — scale with RPS and the slowest path's latency. maxVUs caps memory.
const PRE_VUS = Math.min(2000, Math.max(50, RPS * 3));
const MAX_VUS = Math.min(4000, Math.max(100, RPS * 8));

export const options = {
  // p(99) is NOT in k6's default summary — request it so handleSummary can read it.
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max', 'count'],
  scenarios: {
    ceiling: {
      executor: 'constant-arrival-rate',
      rate: RPS,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: PRE_VUS,
      maxVUs: MAX_VUS,
    },
  },
  // Non-aborting: we WANT to observe the breach, then read the numbers in handleSummary.
  thresholds: {},
};

export function setup() {
  // Login the role each endpoint needs (customer is fine for discovery+booking; login itself
  // hits the public endpoint without a token).
  const customer = login(__ENV.TEST_PHONE || '0820000001', __ENV.TEST_PASSWORD || 'Password123!');
  return { customer };
}

export default function (data) {
  if (ENDPOINT === 'login') {
    // Public, CPU-bound (Argon2). No token. direct → identity:3001/auth/login (no edge limit).
    const url = DIRECT ? `${IDENTITY_URL}/auth/login` : `${BASE_URL}/v1/auth/login`;
    const res = http.post(
      url,
      JSON.stringify({ identifier: __ENV.TEST_PHONE || '0820000001', password: __ENV.TEST_PASSWORD || 'Password123!' }),
      { headers: { 'Content-Type': 'application/json' }, tags: { name: 'login' } }
    );
    check(res, { '200': (r) => r.status === 200 });
    return;
  }
  if (ENDPOINT === 'booking') {
    // Write path + outbox. v2 CreateBookingRequest = { address, scheduled_at (RFC3339), hours,
    // guard_count?, tip? } — base_fee is server-set; `tip` (Decimal) would be a JSON string if sent.
    const body = JSON.stringify({
      address: '123 Sukhumvit Rd, Bangkok',
      scheduled_at: new Date(Date.now() + 86400000).toISOString(),
      hours: 4,
      guard_count: 1,
    });
    const url = DIRECT ? `${BOOKING_URL}/bookings` : `${BASE_URL}/v1/bookings`;
    const res = http.post(url, body, { headers: authHeaders(data.customer), tags: { name: 'booking' } });
    check(res, { '2xx': (r) => r.status >= 200 && r.status < 300 });
    return;
  }
  // discovery (default) — read fan-out, replica-served. direct → booking:3005/available-guards.
  const url = DIRECT ? `${BOOKING_URL}/available-guards` : `${BASE_URL}/v1/available-guards`;
  const res = http.get(url, { headers: authHeaders(data.customer), tags: { name: 'discovery' } });
  check(res, { '200': (r) => r.status === 200 });
}

// One parseable line per run so run-ceiling.sh can table the knee without jq gymnastics.
// `n()` coerces a possibly-missing metric value to a real number (NaN, never undefined) so
// .toFixed never throws inside handleSummary (a summary exception would lose the whole result).
export function handleSummary(data) {
  const n = (m, q) => {
    const v = data.metrics[m] && data.metrics[m].values ? data.metrics[m].values[q] : undefined;
    return typeof v === 'number' ? v : NaN;
  };
  const line =
    `CEILING_RESULT endpoint=${ENDPOINT} target_rps=${RPS} actual_rps=${n('http_reqs', 'rate').toFixed(1)} ` +
    `p95_ms=${n('http_req_duration', 'p(95)').toFixed(2)} p99_ms=${n('http_req_duration', 'p(99)').toFixed(2)} ` +
    `err_rate=${(n('http_req_failed', 'rate') * 100).toFixed(2)}% reqs=${n('http_reqs', 'count')}`;
  return { stdout: '\n' + line + '\n' };
}
