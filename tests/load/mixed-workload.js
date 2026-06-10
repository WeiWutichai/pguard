// Mixed workload — a realistic concurrent "busy hour": many guards streaming GPS while
// customers browse (discovery), a steady trickle of bookings + logins, and chat list reads.
// Runs all scenarios AT ONCE on the local prod stack so contention (DB pool, CPU, gateway) is
// realistic — unlike the per-endpoint ceiling runs which isolate one path.
//
// Ratios (per the v2 baseline shape — a single busy node, scaled to ~1.5× baseline RPS so the
// mix is non-trivial but below the per-endpoint knees found in ceiling-http):
//   GPS WS:        120 concurrent guards × 1 fix/s   (the dominant steady load)
//   discovery:     20 rps   (customers browsing available guards)
//   booking:        6 rps   (conversions — write path + outbox)
//   chat list:     12 rps   (open chat threads)
//   login:          3 rps   (occasional sign-ins; Argon2 — the CPU tax)
// Everything routes through the GATEWAY (the real client path; PR #25 wired chat+presence), so
// this also exercises the edge under a mixed load. Tune the ratios with -e MIX_SCALE=<f>.
import http from 'k6/http';
import ws from 'k6/ws';
import { check } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import { BASE_URL, login, authHeaders } from '../../v1-audit/perf-baseline/scripts/_common.js';

const SCALE = Number(__ENV.MIX_SCALE || 1);
const DURATION = __ENV.DURATION || '60s';
const GPS_VUS = Math.round(120 * SCALE);

// Per-endpoint latency Trends → readable per-path p99 in the mixed run (http_req_duration
// aggregate would blend them). Tagged names mirror the ceiling scripts.
const tLogin = new Trend('mix_login_ms', true);
const tDiscovery = new Trend('mix_discovery_ms', true);
const tBooking = new Trend('mix_booking_ms', true);
const tChat = new Trend('mix_chat_ms', true);
const gpsAccepted = new Counter('mix_gps_accepted');
const gpsFailed = new Counter('mix_gps_conn_failures');

export const options = {
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max', 'count'],
  scenarios: {
    login: {
      executor: 'constant-arrival-rate', exec: 'doLogin',
      rate: Math.max(1, Math.round(3 * SCALE)), timeUnit: '1s', duration: DURATION,
      preAllocatedVUs: 20, maxVUs: 80,
    },
    discovery: {
      executor: 'constant-arrival-rate', exec: 'doDiscovery',
      rate: Math.max(1, Math.round(20 * SCALE)), timeUnit: '1s', duration: DURATION,
      preAllocatedVUs: 40, maxVUs: 150,
    },
    booking: {
      executor: 'constant-arrival-rate', exec: 'doBooking',
      rate: Math.max(1, Math.round(6 * SCALE)), timeUnit: '1s', duration: DURATION,
      preAllocatedVUs: 30, maxVUs: 100,
    },
    chat: {
      executor: 'constant-arrival-rate', exec: 'doChat',
      rate: Math.max(1, Math.round(12 * SCALE)), timeUnit: '1s', duration: DURATION,
      preAllocatedVUs: 30, maxVUs: 120,
    },
    gps: { executor: 'constant-vus', exec: 'doGps', vus: GPS_VUS, duration: DURATION },
  },
  thresholds: {},
};

export function setup() {
  return {
    customer: login(__ENV.TEST_PHONE || '0820000001', __ENV.TEST_PASSWORD || 'Password123!'),
    guard: login(__ENV.GUARD_PHONE || '0810000001', __ENV.GUARD_PASSWORD || 'Password123!'),
  };
}

export function doLogin() {
  const res = http.post(`${BASE_URL}/v1/auth/login`,
    JSON.stringify({ identifier: __ENV.TEST_PHONE || '0820000001', password: __ENV.TEST_PASSWORD || 'Password123!' }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'mix-login' } });
  tLogin.add(res.timings.duration);
  check(res, { 'login 200': (r) => r.status === 200 });
}

export function doDiscovery(data) {
  const res = http.get(`${BASE_URL}/v1/available-guards`, { headers: authHeaders(data.customer), tags: { name: 'mix-discovery' } });
  tDiscovery.add(res.timings.duration);
  check(res, { 'disc 200': (r) => r.status === 200 });
}

export function doBooking(data) {
  const res = http.post(`${BASE_URL}/v1/bookings`,
    JSON.stringify({ address: '123 Sukhumvit Rd', scheduled_at: new Date(Date.now() + 86400000).toISOString(), hours: 4, guard_count: 1 }),
    { headers: authHeaders(data.customer), tags: { name: 'mix-booking' } });
  tBooking.add(res.timings.duration);
  check(res, { 'booking 2xx': (r) => r.status >= 200 && r.status < 300 });
}

export function doChat(data) {
  // chat conversations list — gateway-routed (PR #25). role query param mirrors the baseline.
  const res = http.get(`${BASE_URL}/v1/conversations?role=customer`, { headers: authHeaders(data.customer), tags: { name: 'mix-chat' } });
  tChat.add(res.timings.duration);
  check(res, { 'chat 2xx': (r) => r.status >= 200 && r.status < 300 });
}

export function doGps(data) {
  // GPS direct to presence (isolate the steady fan-in from the edge); the HTTP mix already
  // loads the gateway. 1 fix/sec for the run duration.
  const url = `${(__ENV.PRESENCE_WS || 'ws://presence:3009')}/ws/track`;
  const res = ws.connect(url, { headers: { Authorization: `Bearer ${data.guard}` } }, function (socket) {
    socket.on('open', () => {
      socket.setInterval(() => {
        socket.send(JSON.stringify({ lat: 13.7563 + (Math.random() - 0.5) * 0.05, lng: 100.5018 + (Math.random() - 0.5) * 0.05, accuracy: 10.0, recorded_at: new Date().toISOString() }));
      }, 1000);
    });
    socket.on('message', (msg) => { try { if (JSON.parse(msg).type === 'ack') gpsAccepted.add(1); } catch (_) {} });
    socket.on('error', () => gpsFailed.add(1));
    socket.setTimeout(() => socket.close(), Number(DURATION.replace('s', '')) * 1000 || 60000);
  });
  if (!res || res.status !== 101) gpsFailed.add(1);
}

export function handleSummary(data) {
  const num = (m, q) => {
    const v = data.metrics[m] && data.metrics[m].values ? data.metrics[m].values[q] : undefined;
    return typeof v === 'number' ? v : NaN;
  };
  const p = (m, q) => num(m, q);
  const fr = (m) => num(m, 'rate');
  const ct = (m) => { const v = num(m, 'count'); return Number.isNaN(v) ? 0 : v; };
  const lines = [
    `MIXED scale=${SCALE} duration=${DURATION} gps_vus=${GPS_VUS}`,
    `  login     p95=${p('mix_login_ms', 'p(95)').toFixed(1)}ms p99=${p('mix_login_ms', 'p(99)').toFixed(1)}ms`,
    `  discovery p95=${p('mix_discovery_ms', 'p(95)').toFixed(1)}ms p99=${p('mix_discovery_ms', 'p(99)').toFixed(1)}ms`,
    `  booking   p95=${p('mix_booking_ms', 'p(95)').toFixed(1)}ms p99=${p('mix_booking_ms', 'p(99)').toFixed(1)}ms`,
    `  chat      p95=${p('mix_chat_ms', 'p(95)').toFixed(1)}ms p99=${p('mix_chat_ms', 'p(99)').toFixed(1)}ms`,
    `  gps       accepted=${ct('mix_gps_accepted')} conn_failures=${ct('mix_gps_conn_failures')}`,
    `  http_req_failed=${(fr('http_req_failed') * 100).toFixed(2)}% total_reqs=${ct('http_reqs')}`,
  ];
  return { stdout: '\n' + lines.join('\n') + '\n' };
}
