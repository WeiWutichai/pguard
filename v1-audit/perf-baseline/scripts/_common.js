// Shared helpers for pguard v2 perf-baseline k6 scripts.
// v2 routes through the api-gateway on :3000 under /v1/*. A few services are NOT wired into the
// gateway routing table yet (chat /conversations, presence /ws/track, rating /guards/{id}/ratings).
// The perf harness runs k6 as a container ON the `pguard-prod` compose network, so those scripts
// reach the service directly by Docker DNS (chat:3010 / rating:3007 / presence:3009 via their
// `expose` ports) — no published host ports (the "only the gateway publishes ports" invariant
// stays intact). The localhost defaults below are overridden to the service DNS names at run time.
//
// Override with env vars:
//   BASE_URL     (default http://localhost:3000)  — api-gateway, /v1/* HTTP
//   CHAT_URL     (default http://localhost:3010)  — chat service (direct; not gateway-routed)
//   RATING_URL   (default http://localhost:3007)  — rating service (direct; not gateway-routed)
//   PRESENCE_WS  (default ws://localhost:3009)     — presence WS /ws/track (direct)
//   TEST_PHONE / TEST_PASSWORD   — seeded customer (0820000001 / Password123!)
//   GUARD_PHONE / GUARD_PASSWORD — seeded guard    (0810000001 / Password123!)
//   ADMIN_PHONE / ADMIN_PASSWORD — seeded admin    (0800000001 / Password123!)
import http from 'k6/http';
import { check } from 'k6';

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
export const CHAT_URL = __ENV.CHAT_URL || 'http://localhost:3010';
export const RATING_URL = __ENV.RATING_URL || 'http://localhost:3007';
export const PRESENCE_WS = __ENV.PRESENCE_WS || 'ws://localhost:3009';

// v2 login: POST /v1/auth/login { identifier, password }. identity returns the token pair in the
// body (and sets cookies); we read the body access_token. Returns the access token (or throws).
export function login(phone, password) {
  const res = http.post(
    `${BASE_URL}/v1/auth/login`,
    JSON.stringify({ identifier: phone, password }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'setup-login' } }
  );
  check(res, { 'login 200': (r) => r.status === 200 });
  if (res.status !== 200) {
    throw new Error(`login failed for ${phone}: ${res.status} ${res.body}`);
  }
  const body = res.json();
  const token =
    (body.data && (body.data.access_token || body.data.accessToken)) ||
    body.access_token ||
    body.accessToken;
  if (!token) throw new Error(`no access_token in login body: ${res.body}`);
  return token;
}

export function authHeaders(token) {
  return { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
}
