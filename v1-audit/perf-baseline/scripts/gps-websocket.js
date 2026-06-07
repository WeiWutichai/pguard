// B1.1 — GPS WebSocket load. Opens N concurrent WS connections to presence /ws/track, each
// pushing 1 GPS update/sec. The server enforces ≥1s/connection (presence drops faster updates);
// send ~1/sec to measure the accepted path, RATE_HZ=2 to confirm the drop behaviour.
//
// v2 frame = { lat, lng, accuracy?, recorded_at } (RFC3339; no v1 `type:'location'` wrapper).
// Server acks { type:"ack", recorded_at } after the upsert. presence is NOT gateway-routed in
// v2, so this connects DIRECTLY at PRESENCE_WS (reached by Docker DNS — presence:3009 — when k6
// runs on the compose network) with the guard's Bearer (presence does Bearer-on-upgrade +
// role=guard gate itself).
//
// Vary load: -e STAGE_VUS=10|100|500|1000 (run once per value, record each).
// Run: k6 run -e STAGE_VUS=100 -e GUARD_PHONE=08... -e GUARD_PASSWORD=... gps-websocket.js
import ws from 'k6/ws';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { PRESENCE_WS, login } from './_common.js';

const accepted = new Counter('gps_updates_accepted');
const failed = new Counter('gps_connection_failures');
const ackLatency = new Trend('gps_ack_latency_ms', true);

const VUS = Number(__ENV.STAGE_VUS || 100);
const HOLD = __ENV.HOLD || '60s';
const RATE_HZ = Number(__ENV.RATE_HZ || 1); // 2 → exercise server-side drop

export const options = {
  scenarios: {
    gps: { executor: 'constant-vus', vus: VUS, duration: HOLD },
  },
  thresholds: {
    gps_connection_failures: ['count<' + Math.ceil(VUS * 0.02)], // <2% conn failures
  },
};

// k6 forbids HTTP in the init context — log in ONCE in setup() (one guard token reused by all
// VUs; fine for load shape — for per-guard rows seed N guards and index by __VU).
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
        const lat = 13.7563 + (Math.random() - 0.5) * 0.05;
        const lng = 100.5018 + (Math.random() - 0.5) * 0.05;
        socket.send(JSON.stringify({
          lat,
          lng,
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
      } catch (_) { /* non-JSON heartbeat/ping */ }
    });

    socket.on('error', () => failed.add(1));
    socket.setTimeout(() => socket.close(), Number(HOLD.replace('s', '')) * 1000 || 60000);
  });

  check(res, { 'ws status 101': (r) => r && r.status === 101 });
  if (!res || res.status !== 101) failed.add(1);
}
