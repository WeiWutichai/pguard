// Shared helpers for pguard v1 perf-baseline k6 scripts.
// All scripts hit the nginx gateway. Override with env vars:
//   BASE_URL  (default http://localhost:8080)  — HTTP gateway
//   WS_URL    (default ws://localhost:8080)     — WebSocket gateway
//   TEST_PHONE / TEST_PASSWORD                  — seeded customer login
//   GUARD_PHONE / GUARD_PASSWORD                — seeded guard login (for GPS WS)
import http from 'k6/http';
import { check } from 'k6';

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
export const WS_URL = __ENV.WS_URL || 'ws://localhost:8080';

// Log in via the mobile endpoint, which returns tokens in the JSON body.
// Returns the access token string (or throws so the test fails loudly).
export function login(phone, password) {
  const res = http.post(
    `${BASE_URL}/auth/login/mobile`,
    JSON.stringify({ phone, password }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'setup-login' } }
  );
  check(res, { 'login 200': (r) => r.status === 200 });
  if (res.status !== 200) {
    throw new Error(`login failed for ${phone}: ${res.status} ${res.body}`);
  }
  const body = res.json();
  // tolerate a couple of common envelope shapes
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
