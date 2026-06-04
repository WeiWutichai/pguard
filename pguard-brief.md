# pguard — Architecture Audit + Scaffold + PoC Brief

> **For Claude Code CLI** — paste this into a `claude` session running in `/Users/nest/Documents/guard-dispatch/`. Execute the three phases in order; each phase has a hard gate (review with user before next phase).

---

## Context

The existing folder `/Users/nest/Documents/guard-dispatch/` is the **v1 reference codebase** for a real-time security guard dispatch platform (Thai market). Tech stack: Rust microservices (Axum 0.8) + Flutter mobile + Next.js 16 web admin + PostgreSQL + Redis + MinIO + MediaSoup. See `CLAUDE.md` at that repo root for the full v1 architecture spec.

**Current state:** No production users. Working dev/staging environment. v1 has accumulated tech debt (search for `BUG-` comments to see scope) and a few architectural anti-patterns we want to fix.

**Goal:** Build **`pguard/`** as the canonical sibling folder (at `/Users/nest/Documents/pguard/`) — clean rewrite with the same tech stack but better architecture. The `guard-dispatch/` folder is read-only reference only; the new project drops that name and is simply called **pguard** going forward. New UI comes from a separate Claude Design project (40 HTML files covering 95/101 endpoints — handoff package available separately).

**Decisions already made (do not re-litigate):**
- **Project name:** `pguard` (no hyphen, lowercase). All folders, package names, module names use this.
- **Folder layout:** `/Users/nest/Documents/pguard/` (sibling of `guard-dispatch/`). The v1 folder stays untouched as reference.
- Same primary tech stack (Rust + Flutter + Next.js) — already validated
- **Event bus: NATS** (with JetStream for persistence) — replaces v1's cross-service DB writes
- **Flutter state: Riverpod 2.x** with code generation — replaces v1's Provider
- **API Gateway: scaffolded in Phase 2** (Rust + Axum-as-gateway) — fills in route by route as services migrate
- **Contract-first:** OpenAPI 3.1 specs are single source of truth, codegen Rust handler stubs + Dart + TS clients
- **No backward compatibility needed** (no production users)
- **PoC service: messaging** (notification + chat consolidated) — chosen because it has the worst coupling in v1

---

## Phase 1 — Architecture Audit (NO CODE CHANGES)

Goal: produce a `v1-audit/` directory inside `guard-dispatch/` with six markdown files capturing v1's state, problems, and the rationale that justifies pguard's design. This is the document pguard stands on.

**Run as a `Plan` agent (or `Explore` if Plan is unavailable).** Do not modify any source files.

Files to produce — each one ≤ 1500 words, dense, no fluff:

### `v1-audit/01-current-state.md`
- One-paragraph elevator pitch of what guard-dispatch does
- Service inventory: each Rust service (auth, booking, tracking, notification, chat) + mediasoup → 1-paragraph purpose + key endpoints + DB schemas it owns
- Frontend inventory: count of mobile screens (split by guard/hirer/common) + count of web admin pages + which ones are placeholders
- Database schema map: which schema, which tables, which service writes/reads each table — call out any table written by multiple services (this is the anti-pattern we're fixing)
- Tech inventory: exact versions of all dependencies (`Cargo.toml`, `pubspec.yaml`, `package.json`)

### `v1-audit/02-issues.md`
Six categories, each with concrete file:line citations:
1. **Cross-service coupling** — every place a service touches another service's DB schema directly. Highest-priority issue. CLAUDE.md confirms `booking` does direct INSERTs into `notification.notification_logs` — find every such instance.
2. **Duplicate / legacy screens** — Flutter screens that overlap (e.g. `registration_role_screen.dart` vs `role_selection_screen.dart`, `hirer_history_screen.dart` vs `receipt_list_screen.dart`), files marked deprecated/legacy in comments
3. **State management leaks** — Flutter Provider misuse (mutable state crossing screen boundaries, missing `dispose`)
4. **N+1 queries / missing indexes** — DB queries inside loops, joins without indexes, `SELECT *` in hot paths
5. **`.unwrap()` / `.expect()` in production paths** — every one in `services/*/src/` outside of `main.rs` startup
6. **Bug-tagged areas** — grep `BUG-` comments, group by service, summarize what each tag was about (one line each). This reveals which modules have churn.

### `v1-audit/03-security.md`
Audit JWT/session/auth posture vs. OWASP 2024 + current best practice:
- JWT signing algorithm, key rotation strategy, refresh flow
- Token storage (web cookie vs mobile keychain)
- Rate limiting completeness (which endpoints lack it)
- Audit log completeness (which actions don't write to `audit` schema)
- Input validation gaps (any handler that doesn't validate body)
- File upload posture (magic byte validation present?)
- Specifically check the recent changes around `update_user_role` (CLAUDE.md mentions a security-reviewer flag) — is the fix complete?

### `v1-audit/04-tests.md`
- Test count per service (unit + integration)
- Coverage of critical paths: OTP→PIN→biometric onboarding, booking creation→assignment→payment, GPS WebSocket lifecycle, refund processing
- Missing test categories: load tests, contract tests, E2E
- Flaky test markers if any
- Recommend the minimum test pyramid for v2

### `v1-audit/05-recommendations.md`
The architecture blueprint for v2. Be opinionated. Each recommendation has: **what / why / migration path**.

Required recommendations:
1. **Consolidate notification + chat → messaging service** — both are async pub/sub patterns; splitting them was premature optimization in v1
2. **NATS event bus** for inter-service comms — booking emits `JobAccepted`/`GuardArrived`/etc., messaging subscribes. Eliminates direct DB writes. Use JetStream for at-least-once delivery.
3. **OpenAPI 3.1 contract-first** with codegen pipeline. Spec lives in `contracts/openapi/` per service. Generate Rust handler stubs (utoipa or paperclip), Dart clients (openapi-generator), TS clients (openapi-typescript).
4. **API Gateway** (Rust + Axum) at edge — central auth, rate limiting, observability. Per-service Nginx config in v1 was duplicated logic.
5. **Riverpod 2.x with code generation** for Flutter — `@riverpod` annotations, async-first, type-safe, testable. Provider's mutable state is a known foot-gun for the IndexedStack tab refresh pattern we hit in v1 (BUG-022).
6. **Per-service DB schemas with strict ownership** — `messaging` service owns `messaging` schema, no one else touches it. Cross-service reads happen via API or events, never SQL.
7. **OpenTelemetry first-class** — traces span across services from day 1. Use OTel collector + Grafana Tempo. Critical for debugging real-time WebSocket flows.
8. **Folder structure** (specify exact layout — see Phase 2)

Each recommendation should reference the specific v1 issue from `02-issues.md` it solves.

### `v1-audit/06-migration-plan.md`
Phased plan to get from v1 to pguard. No production users = no backward compat burden, but still phase work to avoid 6-month bang.

Suggested phasing (refine in document):
- **Phase A:** Scaffold pguard repo + contracts pipeline + API gateway skeleton + identity service migration (foundation)
- **Phase B:** Messaging service (this PoC) — proves the event-driven pattern
- **Phase C:** Booking + Pricing migration with event publishing
- **Phase D:** Presence (tracking) migration
- **Phase E:** Calling service (WebRTC) — currently lives inside booking, extract
- **Phase F:** Web admin (Next.js) — port pages incrementally with new design system
- **Phase G:** Mobile (Flutter) — port screens incrementally with Riverpod + new design tokens
- **Phase H:** Decommission v1, archive `guard-dispatch/`, swap DNS

For each phase: scope, exit criteria, risk, time estimate, who's blocked on what.

**Phase 1 exit criteria:** All six files exist, reviewed by user. STOP. Wait for user approval before Phase 2.

---

## Phase 2 — Scaffold `pguard/` Monorepo

Create the sibling directory `/Users/nest/Documents/pguard/` (do NOT touch `guard-dispatch/`).

Build the structure below. Every folder gets a `README.md` explaining what lives there and what doesn't. Every config file is real (not placeholder).

```
pguard/
├── README.md                              # repo orientation + quickstart
├── CLAUDE.md                              # pguard architecture spec (concise — v1's CLAUDE.md got too long)
├── Cargo.toml                             # workspace
├── docker-compose.yml                     # dev stack (Postgres, NATS, Redis, MinIO, OTel collector, Grafana)
├── docker-compose.prod.yml
├── .env.example
├── .editorconfig
├── .gitignore
│
├── apps/
│   ├── web-admin/                         # Next.js 16 App Router only, TypeScript strict
│   │   ├── package.json
│   │   ├── next.config.ts
│   │   ├── app/(dashboard)/page.tsx       # placeholder
│   │   └── README.md
│   ├── mobile/                            # Flutter 3.x + Riverpod 2.x with codegen
│   │   ├── pubspec.yaml
│   │   ├── lib/main.dart                  # ProviderScope boilerplate
│   │   ├── build.yaml                     # riverpod_generator config
│   │   └── README.md
│   └── design-tokens/                     # package: tokens.css from Claude Design + Dart + TS exports
│       ├── package.json
│       ├── tokens.css
│       ├── tokens.dart                    # exported as Flutter ThemeData
│       └── README.md
│
├── services/
│   ├── api-gateway/                       # Rust + Axum, routes to other services
│   │   ├── Cargo.toml
│   │   ├── src/main.rs
│   │   ├── src/routes.rs                  # service routing table — empty initially
│   │   ├── src/auth.rs                    # JWT validation at edge
│   │   ├── src/rate_limit.rs              # tower-governor or custom
│   │   └── README.md
│   ├── identity/                          # placeholder skeleton (Phase A migrates auth here)
│   │   ├── Cargo.toml
│   │   ├── src/main.rs                    # axum server with /healthz only
│   │   └── README.md
│   ├── booking/                           # placeholder
│   ├── presence/                          # placeholder (will be tracking)
│   ├── messaging/                         # ★ Phase 3 will fill this in
│   │   ├── Cargo.toml
│   │   ├── src/main.rs                    # axum server with /healthz only
│   │   └── README.md
│   └── calling/                           # placeholder (WebRTC signaling extracted from booking)
│
├── packages/
│   ├── shared-rust/                       # types, errors, validators, OTel boilerplate
│   │   ├── Cargo.toml
│   │   └── src/lib.rs
│   ├── shared-events/                     # event schemas — JSON Schema + Rust types
│   │   ├── Cargo.toml
│   │   ├── schemas/                       # *.schema.json
│   │   │   ├── job_accepted.schema.json   # event published by booking
│   │   │   ├── guard_arrived.schema.json
│   │   │   ├── job_completed.schema.json
│   │   │   ├── payment_completed.schema.json
│   │   │   ├── chat_message_sent.schema.json
│   │   │   └── review_submitted.schema.json
│   │   └── src/lib.rs                     # serde-deserializable types
│   └── observability/                     # OTel setup, tracing macros, log formatter
│
├── contracts/
│   ├── openapi/                           # OpenAPI 3.1 specs, source of truth
│   │   ├── identity.yaml
│   │   ├── booking.yaml
│   │   ├── presence.yaml
│   │   ├── messaging.yaml                 # ★ Phase 3 fills in fully
│   │   └── calling.yaml
│   ├── asyncapi/                          # AsyncAPI 2.x specs for NATS topics
│   │   └── events.yaml
│   └── db/
│       └── migrations/                    # per-service subfolders
│           ├── identity/
│           ├── booking/
│           ├── presence/
│           ├── messaging/                 # ★ Phase 3 adds initial migrations
│           └── calling/
│
├── infra/
│   ├── docker/                            # per-service Dockerfile.dev and Dockerfile.prod
│   ├── k8s/                               # base manifests + per-env overlays (kustomize)
│   │   ├── base/
│   │   └── overlays/
│   │       ├── dev/
│   │       ├── staging/
│   │       └── prod/
│   ├── terraform/                         # IaC for cloud resources
│   │   └── modules/
│   └── observability/
│       ├── otel-collector.yaml
│       ├── grafana/dashboards/
│       ├── tempo.yaml                     # tracing backend
│       ├── loki.yaml                      # logs backend
│       └── prometheus.yaml                # metrics backend
│
├── tests/
│   ├── e2e/                               # Playwright (web) + Patrol (mobile)
│   ├── contract/                          # Pact contract tests
│   └── load/                              # k6 scripts
│
├── tooling/
│   ├── codegen/                           # OpenAPI → Rust stubs + Dart + TS clients
│   │   ├── README.md
│   │   ├── generate-rust.sh
│   │   ├── generate-dart.sh
│   │   └── generate-ts.sh
│   └── scripts/
│       ├── dev-up.sh                      # docker compose up + tail logs
│       └── reset-db.sh
│
└── .github/
    └── workflows/
        ├── ci.yml                         # per-service build + test
        ├── codegen-check.yml              # fails if specs changed but generated code didn't
        └── security-scan.yml              # cargo-audit, npm audit, snyk
```

**Specific requirements for Phase 2:**

1. **`Cargo.toml` workspace** — pin to Rust 1.83+. Workspace dependencies: `axum = "0.8"`, `tokio = "1"`, `sqlx = "0.8"`, `serde = "1"`, `tracing = "0.1"`, `opentelemetry = "0.27"`, `async-nats = "0.39"`, `utoipa = "5"`. List in `[workspace.dependencies]` so all services inherit.

2. **`docker-compose.yml`** — services: `postgres:16`, `nats:2.10` (with `-js` flag for JetStream), `redis:7`, `minio`, `otel/opentelemetry-collector:0.116`, `grafana/grafana`, `grafana/tempo`, `grafana/loki`. All on a `pguard` network (network name `pguard-dev`). Health checks on each. Use `expose:` not `ports:` except for gateway + grafana.

3. **API gateway skeleton** — Axum server listening on `:8080`, routes `/healthz` and a placeholder routing table that returns 502 with a clear message for unimplemented services. JWT validation middleware ready but no-op until identity service exists.

4. **Observability skeleton** — every service `main.rs` initializes OTel tracer + Prometheus exporter using the shared `packages/observability` crate. Three-line setup, no boilerplate per service.

5. **`apps/mobile/`** — Flutter 3.24+, Riverpod 2.x + riverpod_generator + freezed in `pubspec.yaml`, `build.yaml` configured for codegen, `lib/main.dart` wraps with `ProviderScope`. Add `analysis_options.yaml` with strict lints.

6. **`apps/web-admin/`** — Next.js 16, App Router, TypeScript strict mode, Tailwind v4, no Pages Router files. Import `design-tokens` package via workspace symlink.

7. **`apps/design-tokens/`** — port `tokens.css` from the Claude Design export. Add `tokens.dart` that builds a Flutter `ThemeData` + `tokens.ts` that exports the same values. The handoff zip from Claude Design is at... *(user will paste path or zip the design output before running Phase 2)*.

8. **`.github/workflows/`** — real CI files, not placeholders. `ci.yml` matrix-builds each Rust service, runs `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`, then builds Next.js, runs Flutter analyze + test.

9. **`README.md` at root** — orientation, quickstart (`./tooling/scripts/dev-up.sh`), architecture diagram (ASCII or mermaid), pointer to CLAUDE.md. The project is `pguard` — that name appears in README title, package names, container names, NATS subject prefixes (`pguard.events.*`), Postgres database name (`pguard`), and the docker network (`pguard-dev`).

10. **`CLAUDE.md` for pguard** — concise (target ≤ 400 lines vs v1's 1500+). Sections: services + their responsibilities, event topics, contracts location, dev workflow, do/don't rules. Reference `../guard-dispatch/v1-audit/05-recommendations.md` for rationale instead of inlining it.

**Phase 2 exit criteria:**
- `cd /Users/nest/Documents/pguard && ./tooling/scripts/dev-up.sh` brings up the dev stack with all services healthy (even though they're empty skeletons)
- `cargo build --workspace` succeeds
- `cd apps/web-admin && npm run build` succeeds
- `cd apps/mobile && flutter analyze` returns clean
- README walks a fresh contributor from clone → first PR in <10 minutes

STOP. Wait for user approval before Phase 3.

---

## Phase 3 — PoC: Migrate Messaging Service (notification + chat consolidated)

Goal: port v1's `services/notification/` + `services/chat/` into a single `services/messaging/` inside `pguard/`, replacing all cross-service DB writes with NATS events. This is the architectural pattern every other service will follow — get it right.

### 3.1 Write the contracts first
- **`contracts/openapi/messaging.yaml`** — full OpenAPI 3.1 spec covering: conversations CRUD, messages list, mark-read, attachment upload + signed URL, notifications list, unread count, mark-read, mark-all-read, WebSocket upgrade endpoint (`/ws`). Use v1's CLAUDE.md as reference for shape, but clean up inconsistencies. Tag operations with `conversations`, `messages`, `attachments`, `notifications`, `ws`.
- **`contracts/asyncapi/events.yaml`** — define the events messaging *subscribes to*: `job_accepted`, `guard_en_route`, `guard_arrived`, `job_completed`, `job_cancelled`, `payment_completed`, `review_submitted`, `chat_message_sent`. For each: NATS subject pattern, payload schema (JSON Schema reference), publisher (which service emits it), delivery guarantee (at-least-once).
- **`packages/shared-events/schemas/*.schema.json`** — JSON Schema for each event payload (one file per event type). Strict — all fields required unless explicitly nullable. Include `event_id`, `event_type`, `occurred_at`, `correlation_id` at top level (envelope pattern). NATS subject convention: `pguard.events.<bounded_context>.<event_name>` (e.g. `pguard.events.booking.job_accepted`).
- Run `./tooling/codegen/generate-rust.sh` to produce Rust types in `packages/shared-events/src/generated/` — verify it compiles.

### 3.2 Database schema
- `contracts/db/migrations/messaging/001_init.sql` — combine `notification.notification_logs`, `notification.fcm_tokens`, `chat.conversations`, `chat.messages`, `chat.read_receipts`, `chat.attachments` into a single `messaging` schema. Refactor where v1's schema was awkward:
  - `messaging.devices` (rename from `fcm_tokens`) — generalize for future APNs support
  - `messaging.notifications` — drop the `notification_logs` suffix
  - `messaging.conversations` / `messages` / `read_receipts` / `attachments` — same shape as v1 but in one schema
- `002_indexes.sql` — pre-create all the indexes v1 added later (`idx_otp_codes_phone_purpose`, conversation participant indexes, etc.). Avoid retrofitting.

### 3.3 Implement the service
- `services/messaging/src/main.rs` — Axum server, port 3010. Mounts OpenAPI-generated route stubs.
- `services/messaging/src/handlers/` — REST handlers for all endpoints in the OpenAPI spec.
- `services/messaging/src/ws/` — WebSocket handler for `/ws`. Authenticates via Bearer token in upgrade header (matching v1's mobile auth pattern). Handles both chat messages and live notification streams over the same WS — multiplex by message type.
- `services/messaging/src/events/` — NATS subscriber. Connects to `nats:4222` using `async-nats`. Subscribes to event subjects (e.g. `pguard.events.job_accepted`). For each event, calls the right notification template + sends FCM + writes to `messaging.notifications`. Use JetStream durable consumer for at-least-once.
- `services/messaging/src/fcm/` — FCM HTTP v1 API client (NOT legacy server key). Use Firebase service account JSON, OAuth 2.0 token, send via REST. Match the pattern v1 introduced in migration 044.
- `services/messaging/src/s3/` — MinIO/R2 client for attachments, presigned URL generation, magic byte validation.
- Wire OpenTelemetry traces — spans for: incoming REST, WS message processing, event handling, FCM send, DB writes, S3 ops. Propagate trace context through NATS message headers.
- Wire structured logging via `tracing` crate, JSON formatter, sent to Loki via OTel collector.

### 3.4 Tests
- `services/messaging/tests/integration/` — spin up testcontainers Postgres + NATS, hit real handlers, assert DB state + published messages
- `tests/contract/messaging/` — Pact contract tests asserting the OpenAPI spec matches implementation
- `tests/e2e/messaging.spec.ts` — Playwright test driving the future web admin's chat moderation page (placeholder UI is fine, the test asserts API behavior end-to-end via the gateway)

### 3.5 Gateway wiring
- Add route to `services/api-gateway/src/routes.rs`: requests matching `/messaging/*` → forward to `messaging:3010`. WebSocket upgrades on `/ws/chat` and `/ws/notifications` → forward with header pass-through.

### 3.6 Documentation
- `services/messaging/README.md` — local dev (`cargo run`), test (`cargo test`), event topics consumed/published, NATS subject patterns, FCM setup steps, troubleshooting common issues
- Update root `CLAUDE.md` to add messaging to the service list + reference the README

**Phase 3 exit criteria:**
- `cargo test -p messaging --all-features` passes
- Contract tests pass — implementation matches OpenAPI spec
- E2E test passes — message published to NATS reaches a recipient via FCM (use a test recipient token)
- WebSocket chat works — two browser tabs connect, exchange messages, persist to DB, mark read
- A trace in Grafana Tempo shows the full path: REST → DB → NATS publish → subscriber handler → FCM send
- One service (booking, even just a stub) emits a `job_accepted` event over NATS, messaging consumes it and writes a notification row → no direct cross-service DB write anywhere in messaging

---

## Working notes for the agent

- **No production users** — don't preserve data, don't write migration scripts from v1 schemas to v2 schemas. Fresh DB, fresh start.
- **`guard-dispatch/` is reference, not source** — read from it freely, but never modify. Copy idioms (like JWT validation patterns, magic byte checking) but rewrite in the new structure.
- **The Claude Design output is the UI source of truth** for any visual decisions. If the design tokens conflict with v1's `AppColors`, the design wins.
- **One commit per logical step.** Audit findings → one commit per file. Scaffold → one commit per major folder. PoC → commits per spec/migration/handler/test cluster.
- **Each phase gates on user review.** Do not chain phases. After Phase 1, summarize findings in chat and ask user to read the audit before Phase 2 starts. Same after Phase 2.
- **If a recommendation in `05-recommendations.md` turns out to be wrong during implementation**, update the recommendation file with the revised thinking + reason — keep the audit honest.
- **Time budget.** Phase 1: 30-45 min. Phase 2: ~45 min. Phase 3: 2-4 hours. Adjust freely but flag overruns >50%.

---

## Quickstart for the user

```bash
cd /Users/nest/Documents/guard-dispatch
claude
```

Then in the Claude Code session:

```
Read pguard-brief.md and execute Phase 1. Stop when you're done and summarize what you found in chat.
```

After reviewing the audit:

```
Execute Phase 2 of pguard-brief.md.
```

After reviewing the scaffold:

```
Execute Phase 3 of pguard-brief.md.
```
