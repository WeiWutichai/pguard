// WS lifecycle observer for chaos case 5 (WS-proxy backend dies mid-stream).
// Connects ONE WebSocket to WS_URL with a Bearer, streams 1 GPS fix/sec, and records the
// lifecycle: did it open? how many acks before the cut? did it receive a Close / error when the
// backend was killed mid-stream? Exits after HOLD. The orchestrator (run-chaos.sh) kills the
// presence backend partway through and reads the CHAOS_WS line from handleSummary.
//
//   -e WS_URL=ws://api-gateway:3000/v1/ws/track   (edge-proxied path — the client's real path)
//   -e GUARD_PHONE / -e GUARD_PASSWORD            (seeded guard; logs in via BASE_URL gateway)
//   -e HOLD=20s
import ws from 'k6/ws';
import { Counter } from 'k6/metrics';
import { login } from '../../../v1-audit/perf-baseline/scripts/_common.js';

const opened = new Counter('ws_opened');
const acks = new Counter('ws_acks');
const closed = new Counter('ws_closed');
const errored = new Counter('ws_errored');

const WS_URL = __ENV.WS_URL || 'ws://api-gateway:3000/v1/ws/track';
const HOLD = __ENV.HOLD || '20s';
const HOLD_MS = (Number(HOLD.replace('s', '')) || 20) * 1000;

export const options = { scenarios: { obs: { executor: 'shared-iterations', vus: 1, iterations: 1, maxDuration: HOLD } } };

export function setup() {
  return { token: login(__ENV.GUARD_PHONE || '0810000001', __ENV.GUARD_PASSWORD || 'Password123!') };
}

export default function (data) {
  ws.connect(WS_URL, { headers: { Authorization: `Bearer ${data.token}` } }, function (socket) {
    socket.on('open', () => {
      opened.add(1);
      socket.setInterval(() => {
        socket.send(JSON.stringify({ lat: 13.7563, lng: 100.5018, accuracy: 10.0, recorded_at: new Date().toISOString() }));
      }, 1000);
    });
    socket.on('message', (msg) => { try { if (JSON.parse(msg).type === 'ack') acks.add(1); } catch (_) {} });
    socket.on('close', () => closed.add(1));
    socket.on('error', () => errored.add(1));
    socket.setTimeout(() => socket.close(), HOLD_MS);
  });
}

export function handleSummary(data) {
  const c = (m) => (data.metrics[m] && data.metrics[m].values ? data.metrics[m].values.count : 0);
  const line = `CHAOS_WS opened=${c('ws_opened')} acks=${c('ws_acks')} closed=${c('ws_closed')} errored=${c('ws_errored')}`;
  return { stdout: '\n' + line + '\n' };
}
