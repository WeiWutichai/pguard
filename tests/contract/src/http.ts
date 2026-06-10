// HTTP helpers for hitting the live e2e stack.
//
// Routing in the e2e stack (see infra/docker/docker-compose.e2e.yml + tooling/scripts/e2e-stack-up.sh):
//  - identity / booking / chat  → via the api-gateway on :3000 under the /v1 prefix.
//  - rating                     → ALSO published on a DIRECT host port :3007 (the documented
//    gateway-gap accommodation). We hit rating DIRECTLY so we exercise the rating service's OWN
//    auth/response enforcement — which is exactly what its OpenAPI `security:` block promises, and
//    the surface where the getGuardRatings "was it public?" drift would actually regress.
//
// The gateway auth tier rate-limits ~5 req/s/IP, so we cache one token per account and back off on
// 429. The whole suite runs sequentially (vitest singleFork) for the same reason.

const GATEWAY = process.env.PGUARD_API_BASE_URL ?? "http://localhost:3000";
export const RATING_DIRECT = process.env.PGUARD_RATING_URL ?? "http://localhost:3007";

/** Gateway base WITH the /v1 prefix the gateway strips before proxying. */
export function gatewayUrl(path: string): string {
  return `${GATEWAY}/v1${path}`;
}

export interface Parsed {
  status: number;
  /** Parsed JSON body, or undefined if the response carried no JSON. */
  body: unknown;
  headers: Headers;
  raw: Response;
}

async function parse(res: Response): Promise<Parsed> {
  const text = await res.text();
  let body: unknown = undefined;
  if (text.length > 0) {
    try {
      body = JSON.parse(text);
    } catch {
      body = text; // non-JSON body (surfaced for debugging; schema validation will flag it)
    }
  }
  return { status: res.status, body, headers: res.headers, raw: res };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** fetch + JSON parse, with a small retry on 429 (gateway auth-tier rate limit). */
export async function http(url: string, init?: RequestInit): Promise<Parsed> {
  for (let attempt = 0; attempt < 4; attempt++) {
    const res = await fetch(url, init);
    if (res.status === 429 && attempt < 3) {
      await sleep(400 * (attempt + 1));
      continue;
    }
    return parse(res);
  }
  // unreachable, but keeps the type checker happy
  return parse(await fetch(url, init));
}

export function bearer(token: string): Record<string, string> {
  return { authorization: `Bearer ${token}` };
}

interface TokenPair {
  access_token: string;
  refresh_token: string;
}

const tokenCache = new Map<string, TokenPair>();

/** Log in via the gateway and return the token pair, cached per identifier to spare the rate limit. */
export async function login(identifier: string, password: string): Promise<TokenPair> {
  const key = `${identifier}:${password}`;
  const cached = tokenCache.get(key);
  if (cached) return cached;

  const res = await http(gatewayUrl("/auth/login"), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ identifier, password }),
  });
  if (res.status !== 200) {
    throw new Error(`login(${identifier}) failed: HTTP ${res.status} ${JSON.stringify(res.body)}`);
  }
  // Success envelope: { success, error, data: TokenPair }
  const data = (res.body as { data?: TokenPair } | undefined)?.data;
  if (!data?.access_token) {
    throw new Error(`login(${identifier}): no access_token in response ${JSON.stringify(res.body)}`);
  }
  tokenCache.set(key, data);
  return data;
}

export async function accessToken(account: { identifier: string; password: string }): Promise<string> {
  return (await login(account.identifier, account.password)).access_token;
}

/** Log in WITHOUT touching the shared cache — for tests that then revoke their own token (logout,
 *  refresh-rotation/reuse) and must not invalidate the tokens other tests reuse. Returns the raw
 *  parsed response so the caller can also contract-check the 200 body. */
export async function loginRaw(identifier: string, password: string): Promise<Parsed> {
  return http(gatewayUrl("/auth/login"), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ identifier, password }),
  });
}

/** A minimal but fully-decodable 1×1 JPEG (magic bytes FF D8 FF …), for multipart photo uploads. */
const TINY_JPEG_B64 =
  "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a" +
  "HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIy" +
  "MjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIA" +
  "AhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQA" +
  "AAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3" +
  "ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWm" +
  "p6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEA" +
  "AwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSEx" +
  "BhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElK" +
  "U1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3" +
  "uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iii" +
  "gD//2Q==";

export function tinyJpeg(): Uint8Array {
  return Uint8Array.from(Buffer.from(TINY_JPEG_B64, "base64"));
}
