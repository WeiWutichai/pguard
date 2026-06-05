// Config — loaded from env, fail-fast on anything required missing. Exposed as a pure
// function (throws) so tests can exercise it; `index.js` turns a throw into process.exit(1).

const MIN_SECRET_LEN = 64; // mirrors shared::config::ServiceJwtConfig

/**
 * Build the runtime config from an env map (defaults to process.env).
 * @throws {Error} if a required var is missing/invalid.
 */
export function loadConfig(env = process.env) {
  const serviceJwtSecret = env.SERVICE_JWT_SECRET;
  if (!serviceJwtSecret) {
    throw new Error('SERVICE_JWT_SECRET is required (verifies calling→mediasoup control calls)');
  }
  if (serviceJwtSecret.length < MIN_SECRET_LEN) {
    throw new Error(`SERVICE_JWT_SECRET must be at least ${MIN_SECRET_LEN} characters`);
  }
  const announcedIp = env.MEDIASOUP_ANNOUNCED_IP;
  if (!announcedIp) {
    throw new Error('MEDIASOUP_ANNOUNCED_IP is required (the public IP advertised in ICE candidates)');
  }

  const port = Number(env.MEDIASOUP_PORT || 3011); // control-plane HTTP port (distinct from other svcs)
  const rtcMinPort = Number(env.RTC_MIN_PORT || 40000);
  const rtcMaxPort = Number(env.RTC_MAX_PORT || 49999);
  if (!Number.isInteger(port) || port <= 0) {
    throw new Error('MEDIASOUP_PORT must be a positive integer');
  }
  if (rtcMinPort >= rtcMaxPort) {
    throw new Error('RTC_MIN_PORT must be < RTC_MAX_PORT');
  }

  return { serviceJwtSecret, announcedIp, port, rtcMinPort, rtcMaxPort };
}
