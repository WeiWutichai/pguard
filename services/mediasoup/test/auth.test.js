// Service-JWT control auth tests — the v2 security fix. No native mediasoup needed: the
// auth gate rejects before any media work, and the valid-token case only asserts auth passed.

import assert from 'node:assert/strict';
import test from 'node:test';

import jwt from 'jsonwebtoken';

import { bearerFromHeader, verifyServiceJwt } from '../src/auth.js';
import { loadConfig } from '../src/config.js';
import { createServer } from '../src/server.js';

const SECRET = 'e2e-service-jwt-secret-0123456789-0123456789-0123456789-0123456789-xy';

function mint(overrides = {}) {
  return jwt.sign(
    { sub: 'calling-service', iss: 'pguard', aud: 'pguard-internal', ...overrides },
    overrides.secret || SECRET,
    { algorithm: 'HS256', expiresIn: '60s' },
  );
}

test('verifyServiceJwt accepts a valid pguard-internal token', () => {
  const claims = verifyServiceJwt(mint(), SECRET);
  assert.equal(claims.sub, 'calling-service');
  assert.equal(claims.aud, 'pguard-internal');
});

test('verifyServiceJwt rejects missing / garbage / wrong-audience / wrong-secret', () => {
  assert.throws(() => verifyServiceJwt(undefined, SECRET), /missing service token/);
  assert.throws(() => verifyServiceJwt('not.a.jwt', SECRET));
  assert.throws(() => verifyServiceJwt(mint({ aud: 'pguard' }), SECRET)); // wrong audience
  assert.throws(() => verifyServiceJwt(mint(), 'a-different-secret-of-some-length-aaaaaaaaaaaaaaaa'));
});

test('bearerFromHeader extracts only a Bearer token', () => {
  assert.equal(bearerFromHeader('Bearer abc'), 'abc');
  assert.equal(bearerFromHeader('Basic abc'), undefined);
  assert.equal(bearerFromHeader(undefined), undefined);
});

test('loadConfig fails fast on missing required env', () => {
  assert.throws(() => loadConfig({}), /SERVICE_JWT_SECRET is required/);
  assert.throws(
    () => loadConfig({ SERVICE_JWT_SECRET: SECRET }),
    /MEDIASOUP_ANNOUNCED_IP is required/,
  );
  // A short secret is rejected (mirrors the Rust side).
  assert.throws(
    () => loadConfig({ SERVICE_JWT_SECRET: 'short', MEDIASOUP_ANNOUNCED_IP: '1.2.3.4' }),
    /at least 64 characters/,
  );
  const cfg = loadConfig({ SERVICE_JWT_SECRET: SECRET, MEDIASOUP_ANNOUNCED_IP: '1.2.3.4' });
  assert.equal(cfg.announcedIp, '1.2.3.4');
  assert.equal(cfg.rtcMinPort, 40000);
  assert.equal(cfg.rtcMaxPort, 49999);
});

test('a /control endpoint rejects missing/invalid service-JWT and admits a valid one', async () => {
  const cfg = {
    serviceJwtSecret: SECRET,
    announcedIp: '127.0.0.1',
    port: 0,
    rtcMinPort: 40000,
    rtcMaxPort: 49999,
  };
  const server = createServer(cfg);
  await new Promise((resolve) => server.listen(0, resolve));
  const { port } = server.address();
  const url = `http://127.0.0.1:${port}/control/router-rtp-capabilities`;

  try {
    const noToken = await fetch(url, { method: 'POST' });
    assert.equal(noToken.status, 401, 'missing token → 401');

    const badToken = await fetch(url, {
      method: 'POST',
      headers: { Authorization: 'Bearer not.a.valid.jwt' },
    });
    assert.equal(badToken.status, 401, 'invalid token → 401');

    const wrongAud = await fetch(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${mint({ aud: 'pguard' })}` },
    });
    assert.equal(wrongAud.status, 401, 'wrong audience → 401');

    // Valid token on an SFU-free authed endpoint → 200 (proves the gate admits a good token
    // without spawning a native media worker, keeping the test fast + leak-free). The media
    // endpoint shares the SAME gate — exercised by the reject cases above.
    const good = await fetch(`http://127.0.0.1:${port}/control/ping`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${mint()}` },
    });
    assert.equal(good.status, 200, 'valid service token passes the auth gate');

    // Health is open (no token).
    const health = await fetch(`http://127.0.0.1:${port}/health`);
    assert.equal(health.status, 200);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
