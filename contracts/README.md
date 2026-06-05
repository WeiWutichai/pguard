# contracts/ — the source of truth

Contract-first: edit these specs **before** code. `tooling/codegen` regenerates
clients/stubs from them; generated output is gitignored (commit only the specs).

```
contracts/
├── openapi/      per-service REST APIs (OpenAPI 3.1) — gateway serves them under /v1
├── asyncapi/     NATS JetStream event topics (AsyncAPI 3.0)
└── db/migrations/<svc>/   per-service SQL migrations (strictly per service)
```

## OpenAPI (`openapi/`)
- One `.yaml` per service. First slice: **`notification.yaml`** (CLAUDE.md Kickoff §2.4).
- Standard success envelope `{ success, data }`; errors use `ErrorBody { error: { code, message } }`.
- Two security schemes: `bearerAuth` (user JWT / `access_token` cookie) and
  `serviceAuth` (service-JWT, audience `pguard-internal`) for `/internal/*`.
- **v2 fix encoded in the contract:** `/internal/notifications/push` requires
  `serviceAuth` — v1's `/internal/push` was unauthenticated (audit Issue C).

## AsyncAPI (`asyncapi/`)
- `events.yaml` mirrors `packages/shared-events` (`topics` + `EventEnvelope`).
- Keep the two in lock-step. At-least-once delivery → consumers dedupe on `event_id`.

## DB migrations (`db/migrations/<svc>/`)
- Numbered `NNNN_name.sql`, **one folder per service** (per-service schema ownership).
- **No cross-service foreign keys** — reference foreign aggregates by bare UUID.
- New indexes on populated tables → `CREATE INDEX CONCURRENTLY` (own migration).

## Codegen targets (see `tooling/codegen/`)
| Spec | Output (gitignored) |
|---|---|
| `openapi/*.yaml` | Rust types/handler stubs · `apps/mobile/lib/api/generated/` (Dart) · `apps/web-admin/src/api/generated/` (TS) |
| `asyncapi/events.yaml` | event payload types (cross-checked against `packages/shared-events`) |
