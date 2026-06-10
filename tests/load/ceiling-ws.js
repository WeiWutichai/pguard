// Ceiling finder (GPS WebSocket) — N concurrent /ws/track connections, each pushing 1 fix/sec.
// run-ceiling.sh calls this at INCREASING -e STAGE_VUS to find where connection failures appear
// or ack p99 degrades. presence enforces ≥1 s/connection, so a fraction of sends is dropped by
// design (sent − accepted); we watch FAILURES and ack latency, not the drop.
//
// presence is gateway-routed in v2 now (PR #25 wired /v1/ws/track), but the baseline harness
// connects DIRECTLY to presence to isolate the presence ceiling from the edge. Keep that here:
// -e PRESENCE_WS=ws://presence:3009 measures the SERVICE ceiling; point it at the gateway
// (ws://api-gateway:3000/v1) to measure the edge-proxied path instead (documented in RESULTS.md).
import ws from 'k6/ws';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { PRESENCE_WS, login } from '../../v1-audit/perf-baseline/scripts/_common.js';

const accepted = new Counter('gps_updates_accepted');
const failed = new Counter('gps_connection_failures');
const ackLatency = new Trend('gps_ack_latency_ms', true);

const VUS = Number(__ENV.STAGE_VUS || 100);
const HOLD = __ENV.HOLD || '30s';
const RATE_HZ = Number(__ENV.RATE_HZ || 1);

export const options = {
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max', 'count'],
  scenarios: { gps: { executor: 'constant-vus', vus: VUS, duration: HOLD } },
  thresholds: {},
};

export function setup() {
  return { token: login(__ENV.GUARD_PHONE || '0810000001', __ENV.GUARD_PASSWORD || 'Password123!') };
}

export default function (data) {
  const url = `${PRESENCE_WS}/ws/track`;
  const params = { headers: { Authorization: `Bearer ${data.token}` } };
  const res = ws.connect(url, params, function (socket) {
    socket.on('open', () => {
      socket.setInterval(() => {
        const sentAt = Date.now();
        socket.send(JSON.stringify({
          lat: 13.7563 + (Math.random() - 0.5) * 0.05,
          lng: 100.5018 + (Math.random() - 0.5) * 0.05,
          accuracy: 10.0,
          recorded_at: new Date(sentAt).toISOString(),
        }));
      }, Math.floor(1000 / RATE_HZ));
    });
    socket.on('message', (msg) => {
      try {
        const m = JSON.parse(msg);
        if (m.type === 'ack') {
          accepted.add(1);
          if (m.recorded_at) ackLatency.add(Date.now() - Date.parse(m.recorded_at));
        }
      } catch (_) { /* heartbeat */ }
    });
    socket.on('error', () => failed.add(1));
    socket.setTimeout(() => socket.close(), Number(HOLD.replace('s', '')) * 1000 || 30000);
  });
  check(res, { 'ws 101': (r) => r && r.status === 101 });
  if (!res || res.status !== 101) failed.add(1);
}

export function handleSummary(data) {
  const n = (m, q) => {
    const v = data.metrics[m] && data.metrics[m].values ? data.metrics[m].values[q] : undefined;
    return typeof v === 'number' ? v : NaN;
  };
  // A k6 Counter that never incremented is absent from data.metrics → report 0 (and so the
  // run-ceiling.sh `conn_failures=<int>` regex always matches).
  const cnt = (m) => { const v = n(m, 'count'); return Number.isNaN(v) ? 0 : v; };
  const line =
    `CEILING_WS conns=${VUS} accepted=${cnt('gps_updates_accepted')} ` +
    `conn_failures=${cnt('gps_connection_failures')} ` +
    `ack_p95_ms=${n('gps_ack_latency_ms', 'p(95)').toFixed(1)} ack_p99_ms=${n('gps_ack_latency_ms', 'p(99)').toFixed(1)} ` +
    `ws_connect_p99_ms=${n('ws_connecting', 'p(99)').toFixed(1)}`;
  return { stdout: '\n' + line + '\n' };
}
