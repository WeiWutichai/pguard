<!-- pguard v2 scaffold stub — codegen overview. See CLAUDE.md "API contracts". -->
# Codegen — OpenAPI 3.1 → typed clients & stubs

**Source of truth:** `contracts/openapi/*.yaml` (per-service OpenAPI 3.1) and
`contracts/asyncapi/events.yaml` (NATS event topics). Hand-editing generated code is
forbidden — change the spec, then regenerate.

See CLAUDE.md → architecture decision *"API contracts: OpenAPI 3.1 as source of truth →
codegen Rust handler stubs + Dart + TS clients"*.

## Targets

| Target | Generated into | Consumed by |
|---|---|---|
| Rust types + Axum handler stubs | `packages/shared-rust/src/generated/` | `services/<svc>/api/` (thin transport) |
| Rust event serde types | `packages/shared-events/src/generated/` | services emitting/consuming NATS events |
| Dart API client | `apps/mobile/lib/api/generated/` | Flutter (Riverpod controllers) |
| TS API client | `apps/web-admin/src/api/generated/` | Next.js (all API calls go through this client) |

## Rules

- **All generated output is gitignored** (see repo `.gitignore`). Commit only the specs.
- Regenerate after any change to `contracts/openapi/` or `contracts/asyncapi/`.
- Rust handlers are *stubs*: codegen emits trait/signature; real logic lives in `domain/`
  (DB/HTTP-free) per CLAUDE.md per-service layering.
- Run via `./tooling/codegen/generate.sh` (idempotent; safe to re-run).

## Tooling (to be wired)

Each target is a TODO until the generator binaries are pinned. Candidate generators:
- Rust: `openapi-generator` (rust-axum) or `progenitor`
- Dart: `openapi-generator` (dart-dio)
- TS: `openapi-typescript` + `openapi-fetch`
- AsyncAPI: `@asyncapi/generator`

Pin exact versions here once chosen so codegen is reproducible across machines/CI.
