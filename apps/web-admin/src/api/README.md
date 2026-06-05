# web-admin API client

This is a pguard v2 scaffold stub.

## How API access works here

Per `CLAUDE.md` › **Web (Next.js)** Do/Don't:

- **All API calls go through the generated TypeScript client** — never hand-roll
  `fetch()` against backend services from components.
- The client is generated from the OpenAPI source of truth in
  `contracts/openapi/` (per-service `.yaml`) by `tooling/codegen/`.

## Where generated code lands

The generated client is written to:

```
src/api/generated/
```

That directory is **gitignored** (see the repo `.gitignore`) — it is a build
artifact, regenerated from `contracts/openapi/`, never edited by hand.

## Auth & CSRF (reminder)

- Cookie-based auth only: **httpOnly, Secure, SameSite=Lax**. Never `localStorage`.
- Send a **CSRF token** on all state-changing endpoints (POST/PUT/PATCH/DELETE).

## TODO

- TODO(tooling/codegen): add the OpenAPI → TS client generation step and wire it
  into a `pnpm` script (e.g. `gen:api`).
- TODO: add a thin `src/api/client.ts` wrapper that injects credentials
  (`credentials: "include"`) and the CSRF header, re-exporting the generated client.
