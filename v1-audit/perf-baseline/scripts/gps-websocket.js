// B1.1 — GPS WebSocket load.
// Opens N concurrent WS connections to /ws/track, each pushing 1 GPS update/sec.
// Server enforces max 1 update/sec/connection (tracking/src/handlers.rs) — updates
// sent faster are silently dropped. We send at exactly ~1/sec to measure the
// accepted path, and a STRESS mode (2/sec) to confirm the drop behaviour.
//
// Vary load with: -e STAGE_VUS=10|100|500|1000  (run once per value, record each)
// Run:  k6 run -e STAGE_VUS=100 -e GUARD_PHONE=08... -e GUARD_PASSWORD=... gps-websocket.js
import ws from 'k6/ws';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { WS_URL, login } from './_common.js';

const accepted = new Counter('gps_updates_accepted');
const failed = new Counter('gps_connection_failures');
const ackLatency = new Trend('gps_ack_latency_ms', true);

const VUS = Number(__ENV.STAGE_VUS || 100);
const HOLD = __ENV.HOLD || '60s';
const RATE_HZ = Number(__ENV.RATE_HZ || 1); // set 2 to exercise server-side drop

export const options = {
  scenarios: {
    gps: { executor: 'constant-vus', vus: VUS, duration: HOLD },
  },
  thresholds: {
    gps_connection_failures: ['count<' + Math.ceil(VUS * 0.02)], // <2% conn failures
  },
};

// One token reused by all VUs (same seeded guard is fine for load shape; for
// realistic per-guard rows, seed N guards and index by __VU).
const TOKEN = login(__ENV.GUARD_PHONE || '0810000001', __ENV.GUARD_PASSWORD || 'Password123!');

export default function () {
  const url = `${WS_URL}/ws/track`;
  const params = { headers: { Authorization: `Bearer ${TOKEN}` } };

  const res = ws.connect(url, params, function (socket) {
    let seq = 0;
    socket.on('open', () => {
      socket.setInterval(() => {
        seq += 1;
        const sentAt = Date.now();
        // jitter a path around Bangkok
        const lat = 13.7563 + (Math.random() - 0.5) * 0.05;
        const lng = 100.5018 + (Math.random() - 0.5) * 0.05;
        socket.send(JSON.stringify({ type: 'location', lat, lng, ts: sentAt, seq }));
      }, Math.floor(1000 / RATE_HZ));
    });

    socket.on('message', (msg) => {
      // server ack / echo — measure round trip if it carries our ts
      try {
        const m = JSON.parse(msg);
        if (m.ts) ackLatency.add(Date.now() - m.ts);
        if (m.type === 'ack' || m.accepted) accepted.add(1);
      } catch (_) { /* non-JSON heartbeat/ping */ }
    });

    socket.on('error', () => failed.add(1));
    socket.setTimeout(() => socket.close(), Number(HOLD.replace('s', '')) * 1000 || 60000);
  });

  check(res, { 'ws status 101': (r) => r && r.status === 101 });
  if (!res || res.status !== 101) failed.add(1);
}
