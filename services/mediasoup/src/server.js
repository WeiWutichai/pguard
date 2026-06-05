// HTTP control plane. `/health` is open; every `/control/*` endpoint is gated by a
// service-JWT (the v2 security fix). The media operations themselves run on the SFU router.

import http from 'node:http';

import { bearerFromHeader, verifyServiceJwt } from './auth.js';
import { getRouter, sfuAvailable } from './sfu.js';

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(payload);
}

/**
 * Build the control server. Returns an unstarted `http.Server` so callers (and tests) own
 * the `listen` call.
 * @param {{serviceJwtSecret: string, announcedIp: string, rtcMinPort: number, rtcMaxPort: number}} config
 */
export function createServer(config) {
  return http.createServer(async (req, res) => {
    const url = req.url || '/';

    // Liveness — never authenticated.
    if (req.method === 'GET' && url === '/health') {
      sendJson(res, 200, { status: 'ok', service: 'mediasoup' });
      return;
    }

    // Everything under /control/* requires a valid service-JWT.
    if (url.startsWith('/control/')) {
      const token = bearerFromHeader(req.headers['authorization']);
      try {
        verifyServiceJwt(token, config.serviceJwtSecret);
      } catch {
        // Generic 401 — never reveal why (missing vs invalid vs expired).
        sendJson(res, 401, { error: 'unauthorized' });
        return;
      }

      // Authenticated liveness for the control plane — proves the service-JWT was accepted
      // without touching the media engine (used by callers + tests to verify auth wiring).
      if (req.method === 'POST' && url === '/control/ping') {
        sendJson(res, 200, { ok: true });
        return;
      }

      // Authenticated control operations.
      if (req.method === 'POST' && url === '/control/router-rtp-capabilities') {
        try {
          const router = await getRouter(config);
          sendJson(res, 200, { rtpCapabilities: router.rtpCapabilities });
        } catch (e) {
          // The auth passed; the media engine just isn't available. Log the detail
          // server-side; return a generic body (no internal leak, matching the 401 path).
          console.error('[mediasoup] router-rtp-capabilities failed:', e);
          sendJson(res, 503, { error: 'sfu unavailable' });
        }
        return;
      }

      sendJson(res, 404, { error: 'unknown control endpoint' });
      return;
    }

    sendJson(res, 404, { error: 'not found' });
  });
}

/** Start the server; logs the bound port + whether the media engine is available. */
export async function start(config) {
  const server = createServer(config);
  await new Promise((resolve) => server.listen(config.port, resolve));
  const hasSfu = await sfuAvailable();
  console.log(
    `[mediasoup] control plane on :${config.port} ` +
      `(announcedIp=${config.announcedIp}, rtc=${config.rtcMinPort}-${config.rtcMaxPort}, ` +
      `sfu=${hasSfu ? 'ready' : 'NOT INSTALLED'})`,
  );
  return server;
}
