<!-- pguard v2 scaffold stub — contract tests. See CLAUDE.md "tests/contract". -->
# Contract tests — Pact

Verify producers and consumers stay aligned with the contracts that are the source of truth:

- **HTTP:** `contracts/openapi/*.yaml` (OpenAPI 3.1) — gateway/service request/response shapes.
- **Events:** `contracts/asyncapi/events.yaml` — NATS topic payloads + the shared event
  envelope (`event_id`, `event_type`, `occurred_at`, `correlation_id`, `payload`).

## Approach

- **Consumer-driven Pact** between services (e.g. notification consumes booking events;
  web/mobile clients consume gateway responses).
- Generated clients (`tooling/codegen`) are exercised against provider stubs so a spec
  drift breaks the build, not production.
- Provider verification runs in each service's CI against published pacts.

## Layout (create as services land)

```
tests/contract/
├── consumers/   pacts authored by consumers (services, web, mobile)
└── providers/   provider-side verification config per service
```

## Rules

- A contract change starts in `contracts/` then regenerates clients — never patch generated code.
- Event contracts must include the envelope + idempotency-key semantics (at-least-once delivery).
