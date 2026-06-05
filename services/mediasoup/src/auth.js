// Service-JWT verification — the v2 fix for the v1 gap where mediasoup control calls were
// unauthenticated. Mirrors `shared::service_jwt`: HS256, iss="pguard", aud="pguard-internal".
// Every calling→mediasoup control call MUST carry such a token.

import jwt from 'jsonwebtoken';

const ISSUER = 'pguard';
const AUDIENCE = 'pguard-internal';

/**
 * Verify a service-JWT string. Returns the decoded claims, or throws if missing/invalid/
 * expired/wrong-audience.
 * @param {string|undefined} token
 * @param {string} secret
 */
export function verifyServiceJwt(token, secret) {
  if (!token) {
    throw new Error('missing service token');
  }
  // Throws on bad signature / exp / iss / aud — exactly the checks shared's decoder makes.
  return jwt.verify(token, secret, {
    algorithms: ['HS256'],
    issuer: ISSUER,
    audience: AUDIENCE,
  });
}

/** Extract a Bearer token from an `Authorization` header value, or `undefined`. */
export function bearerFromHeader(headerValue) {
  if (typeof headerValue !== 'string') return undefined;
  const prefix = 'Bearer ';
  return headerValue.startsWith(prefix) ? headerValue.slice(prefix.length) : undefined;
}
