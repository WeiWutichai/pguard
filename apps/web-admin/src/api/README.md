# web-admin API client

All backend access goes through the **generated TypeScript client** (CLAUDE.md › Web) — never a
hand-rolled `fetch` against a service. The client is generated from the OpenAPI source of truth in
`contracts/openapi/` and wrapped with [`openapi-fetch`](https://openapi-ts.dev/openapi-fetch/).

## Layout

```
src/api/generated/identity.ts   # types from contracts/openapi/identity.yaml
src/api/generated/profile.ts    # types from contracts/openapi/profile.yaml
src/lib/api.ts                  # openapi-fetch clients (identityApi, profileApi)
src/lib/session.ts              # server-side GET /auth/me (cookie-forwarded)
```

## Regenerate

```bash
pnpm gen:api          # openapi-typescript → src/api/generated/{identity,profile}.ts
# (or, from the repo root: tooling/codegen/generate.sh runs the ts-client target)
```

Run this whenever the OpenAPI contracts change.

## Why the generated client is COMMITTED (not gitignored)

The prod Docker image (`infra/docker/web-admin.Dockerfile`) copies only `apps/web-admin/` into the
builder — **not** the repo's `contracts/` dir — so it can't regenerate at build time. Committing the
generated types keeps `pnpm build` reproducible there. (This intentionally diverges from the other
`*/generated/` dirs, whose builds run codegen as a step.)

## Auth & CSRF

- Cookie-based auth only: the gateway/identity set the **httpOnly `access_token`** cookie on login;
  `lib/api.ts` uses `credentials: "include"`. Never `localStorage`.
- The client middleware adds **`X-Requested-With`** on state-changing (non-GET/HEAD) calls — the
  gateway enforces it for cookie auth (CSRF).
- The browser hits a same-origin `/v1` (proxied to the gateway via `next.config.ts` rewrites) so the
  cookies stay first-party.
