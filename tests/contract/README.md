# Contract tests

Guards against **contract drift** between the running services and the source-of-truth contracts —
in CI, not in staging. Two drifts, both caught here:

1. **Provider drift** — a service changes a response shape / status / auth behaviour but the
   contract (`contracts/openapi/*.yaml`, `contracts/asyncapi/events.yaml`) wasn't updated.
2. **Consumer drift** — a generated client in the repo expects a shape the provider no longer
   gives (the committed web-admin TS client is regenerated and byte-diffed).

## Approach (and why)

We use **provider verification driven straight from the OpenAPI/AsyncAPI documents** rather than
full consumer-driven Pact. Rationale (lowest maintenance that still *proves* something):

- The committed contracts are already the source of truth and are codegen'd into clients. A Pact
  broker + can-i-deploy workflow would add a stateful service and per-consumer pact authoring for a
  v2 with no production consumers yet — cost without payoff today.
- Instead we hit the **real services on the real stack** and validate every response **against the
  schema extracted from the committed contract** (Ajv, JSON-Schema-2020-12). The schema is read from
  the YAML at test time and dereferenced — never re-typed — so the test compares the provider to the
  *actual contract*, not to a hand-written copy that could drift in lockstep. That is the difference
  between a real contract test and a tautology.
- `meta/validator.contract.test.ts` is the **anti-tautology guard**: it proves the validator
  *rejects* a non-conforming payload and *accepts* a conforming one, with no stack required. If that
  file ever green-lights a malformed payload, nothing else here can be trusted.

Tooling: `vitest` (runner) + `ajv`/`ajv-formats` (2020-12 validation) +
`@apidevtools/json-schema-ref-parser` (deref). The specs are OpenAPI 3.1 but were authored with the
3.0 `nullable: true` keyword in places; `src/specs.ts` normalizes that into real 2020-12 nullability
so Ajv validates them as intended.

## What is covered

| Area | File | Notes |
|---|---|---|
| Validator self-proof | `meta/validator.contract.test.ts` | No stack. Schemas compile; bad payloads rejected. |
| identity (HTTP) | `http/identity.contract.test.ts` | login / me / logout+revoke / refresh+reuse, role matrix, edge-401. |
| booking (HTTP) | `http/booking.contract.test.ts` | reads, create happy/400, role 403s. |
| rating (HTTP) | `http/rating.contract.test.ts` | **getGuardRatings auth-drift guard**, admin list/visibility, review 401/409. |
| chat (HTTP) | `http/chat.contract.test.ts` | conversations CRUD, messages, read, attachment upload, IDOR 403. |
| events | `events/events.contract.test.ts` | `job_accepted`, `progress_reported`, `user.approved` envelopes from the outbox. |

**Error envelope nuance.** Service-originated errors carry the documented `ErrorBody`
`{error:{code,message}}` and are validated against the contract. **Edge-originated 401s** (a
tokenless call to a protected route, rejected by the gateway before it reaches the service) carry
the gateway's own `{success:false,error:"<string>"}` envelope — a known divergence; for those we
assert the status + rejection, not the service schema.

**rating `getGuardRatings` is the canonical historical drift.** Its contract declares
`security: bearerAuth` and documents that auth is enforced *at the edge*. The service handler now
also validates (`services/rating/src/api/mod.rs` `guard_ratings` takes an `AuthUser` —
defense-in-depth, pre-smoke-cleanup #3). The auth-required assertion still hits the **gateway** (the
surface the contract promises to protect): an unauthenticated `GET /v1/guards/{id}/ratings` must be
`401`. If the route is ever made edge-public again, that test goes red.

re-coded from `CONFLICT` → `DUPLICATE_CHECK_IN` by the parallel `feat/checkin-409-subcode` slice.
The duplicate test asserts the *envelope shape* (stable) and accepts **either** code, so it stays
green across that merge. **Rebase after that slice lands** and tighten to `DUPLICATE_CHECK_IN`.

## Running locally

```bash
# 1. Bring the real stack up (reuses tooling/scripts/e2e-stack-up.sh, adds the chat service).
#    Needs Docker. ~first run builds the service images.
tests/contract/stack-up.sh

# 2. Install + run the suite.
cd tests/contract
pnpm install --frozen-lockfile
pnpm test                 # everything (meta + http + events)
pnpm test:http            # just the HTTP provider checks
pnpm test:events          # just the event-contract checks
pnpm exec vitest run meta # just the validator self-proof (no stack needed)

# 3. The consumer-side stale-client guard (no stack needed):
tests/contract/check-generated-clients.sh
```

Env (defaults match the e2e harness): `PGUARD_API_BASE_URL` (gateway, default
`http://localhost:3000`), `PGUARD_RATING_URL` (rating direct, default `http://localhost:3007`).
Outbox reads use `docker compose exec postgres psql` by default; set `PGUARD_E2E_PSQL` to a direct
`psql ...` invocation for a non-docker DB.

## Adding the next service

The suite starts with 4 services (identity · booking · rating · chat) and a reusable pattern. To add
one (e.g. `payment`):

1. Add its key to `ServiceKey` in `src/specs.ts` (the loader already resolves
   `contracts/openapi/<key>.yaml`).
2. Create `http/payment.contract.test.ts`. For each endpoint:
   - send a real request through the right surface (gateway `/v1/...`, or a direct host port if the
     service is gateway-gapped — see `infra/docker/docker-compose.e2e.yml`);
   - `await assertResponseMatchesSpec("payment", method, "/path/{template}", res)` for happy + error
     responses (the **path template as written in the spec**, not the concrete URL);
   - assert auth with `requiresUserBearer(...)` derived from the contract's `security:`.
3. If the service isn't in the e2e `SERVICES` list, add it in `stack-up.sh` the same way `chat` is
   added (don't edit the shared `tooling/scripts/e2e-stack-up.sh`).
4. For a new event: `assertEventMatchesSchema("EnvelopeOf_X", envelopeReadFromOutbox)`.

## Out of scope (TODO)

- Pact broker + `can-i-deploy` (deferred — no production consumers to gate yet).
- The remaining services (payment, profile, otp, presence, calling, notification) — the pattern
  above makes each a small addition.
- `gen:api` only covers 6 specs (no `otp`, no `chat`), so the stale-client guard does not cover those
  two contracts; extend `apps/web-admin`'s `gen:api` to include them if/when a TS client needs them.
