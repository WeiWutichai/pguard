<!-- pguard v2 — codegen. See CLAUDE.md "API contracts". -->
# Codegen — contracts → typed clients & event types

**Source of truth:** `contracts/openapi/*.yaml` (per-service OpenAPI 3.1) and
`contracts/asyncapi/events.yaml` (NATS event topics). **Never hand-edit generated code** —
change the spec, then regenerate. Generated output is **committed** (so CI can `git diff` it for
drift); the build-time artifacts it produces (`*.g.dart`) stay gitignored.

```bash
./tooling/codegen/generate.sh        # runs every wired target (idempotent — re-run ⇒ no diff)
```

## Target matrix

| Target | Tool (pinned) | Output | Committed? | Status |
|---|---|---|---|---|
| **TS client** (web-admin) | `openapi-typescript ^7` + `openapi-fetch` | `apps/web-admin/src/api/generated/<svc>.ts` | ✅ | done (PR #32) |
| **Dart client** (mobile) | `openapi-generator` **dart-dio** — CLI `@openapitools/openapi-generator-cli@2.15.3` → generator **7.14.0** (`openapitools.json`) | `apps/mobile/lib/api/generated/<svc>/` | ✅ | **done — not yet adopted** |
| **Rust event types** | in-repo `gen_rust_events.py` (python3 + `PyYAML==6.0.2`) | `packages/shared-events/src/generated/events.rs` | ✅ | **done — not yet adopted** |
| **Rust Axum handler stubs** | — | `packages/shared-rust/src/generated/` | — | **SKIPPED (see below)** |

Each target checks its toolchain and SKIPs loudly if it is missing, so a partial environment
still runs what it can. Reproducibility is pinned per the table (CLI + generator versions, the
PyYAML version, the openapi-typescript major); CI regenerates and fails on any diff.

## CI stale-checks (drift guards)

- **TS** — `tests/contract/check-generated-clients.sh` (the `contract-tests` job).
- **Dart + Rust events** — `tests/contract/check-generated-codegen.sh` (the `codegen-stale` job:
  Node+pnpm for the pinned openapi-generator CLI, **Java 17** for the JVM generator, Python for the
  rust-events generator). Both regenerate from the contracts and `git diff --exit-code` — a
  contract edited without regenerating fails CI.

## Adding a NEW spec

1. Add `contracts/openapi/<svc>.yaml` (or a new schema to `contracts/asyncapi/events.yaml`).
2. **TS:** add the spec to `apps/web-admin` `gen:api` (package.json).
3. **Dart:** add `<svc>` to the `SPECS=(…)` array in `generate.sh`.
4. **Rust events:** `gen_rust_events.py` emits a struct for every `EnvelopeOf_*` schema
   automatically — for a **flat scalar** payload there is nothing to do but add a drift-lock test
   in `packages/shared-events/tests/drift_lock.rs`. A payload with a **nested object, array, or
   `$ref`** is not supported yet: codegen fails loudly (`unsupported non-scalar schema leaf at
   <Struct>.<field>`) — extend `rust_type()` + the field walker first.
5. `./tooling/codegen/generate.sh` && commit the generated output.

## Why dart-dio + `--skip-validate-spec`

`dart-dio` (built_value) represents our complex 3.1 schemas (e.g. identity's nested PDPA
`data_export`) correctly — the plain `-g dart` generator emits broken code for them. The
generated package is self-contained (own `pubspec.yaml`), so it is **excluded from the app's
`flutter analyze`** (`analysis_options.yaml` → `lib/api/generated/**`) and validated standalone
(`flutter pub get && dart run build_runner build && dart analyze` ⇒ clean but for cosmetic
unused-import warnings). `--skip-validate-spec`: our specs omit the OPTIONAL
`info.license.identifier`/`url`, which generator 7.14 validates over-strictly; the specs are valid
OpenAPI 3.1. **Adoption is out of scope** — the mobile app keeps its hand-written dio client; the
generated client is a compile-time proof the contracts are representable in Dart + a head-start
for new features. See `apps/mobile/lib/api/README.md`.

## Why the Rust event types are a small in-repo generator

shared-events already hand-writes the GENERIC `EventEnvelope<T>`; only the 11 typed **payloads**
need generating, and each lives as the `payload` sub-schema inside an AsyncAPI `EnvelopeOf_*`
`allOf`. A ~120-line python script extracts exactly those — no Java/Docker, reproducible on any CI
runner with `python3 + PyYAML`. The generated structs are a **contract-lock, not yet adopted**:
`packages/shared-events/tests/drift_lock.rs` pins each one to the exact JSON the producing service
emits today (transcribed from the real `serde_json::json!` payloads), so an un-regenerated
`events.yaml` edit turns the suite red. Switching the services from inline `json!` to these typed
payloads is a documented follow-up.

## Skipped: Rust Axum handler stubs

Deliberately **not** generated (and not a TODO). The 11 services are hand-written and complete, and
the **contract tests (PR #32)** already verify every provider against its OpenAPI spec at runtime.
Generating trait/handler stubs now would be churn against finished code with no consumer, and risks
fighting the bespoke per-service `domain/`/`repo/`/`api/` layering (CLAUDE.md). Revisit when a NEW
service is scaffolded from a spec — then stub-gen earns its keep. The
`packages/shared-rust/src/generated/` dir stays gitignored so a local experiment can't leak in.
