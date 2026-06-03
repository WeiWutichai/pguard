# pguard — Architecture Spec

> **Real-time Security Guard Dispatch Platform** (Thai market) — v2 of guard-dispatch
> **State:** Bootstrapping. v1 reference lives at `../guard-dispatch/`. Audit findings drive the v2 design.

Keep this file ≤ 400 lines. Detailed rationale lives in `../guard-dispatch/v2-audit/` (don't inline it).

---

## What pguard is

Customer-side mobile app books on-demand security guards. Guards receive jobs, navigate to location, check in hourly with photo+GPS, complete work. Web admin onboards guards, manages payments/refunds, monitors operations. Bilingual TH/EN.

Stack: Rust microservices (Axum) + Flutter mobile + Next.js 16 web admin + PostgreSQL + NATS + Redis + MinIO/R2.

---

## Architecture decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| Project name | `pguard` (no hyphen) | folder, packages, container, NATS subject `pguard.events.*`, DB `pguard`, network `pguard-dev` |
| Inter-service comms | **NATS JetStream** events | replaces v1 cross-schema direct writes (Issue C1) |
| Cross-tx consistency | Transactional outbox | atomic business+event |
| Service auth (internal) | Service-JWT (`sub="<svc-name>-service"`, separate secret) | v1 `/internal/push` had no auth |
| API contracts | **OpenAPI 3.1** as source of truth | codegen Rust handler stubs + Dart + TS clients |
| API versioning | `/v1/` prefix at gateway, per-resource bump for breaking changes | mobile/web transition without coordination |
| Flutter state | **Riverpod 2.x** + codegen | replaces Provider god-providers |
| Mobile real-time | **WebSocket subscription** for booking status | replaces 13-timer REST polling (BUG cluster source) |
| Token revocation | `token_revocation_version` per-user + jti blocklist | adds force-revoke-all on top of v1's per-token revoke |
| Refresh rotation | Family + rotation_id (RFC 6749 §6) | reuse detection → revoke family + alert |
| Observability | OpenTelemetry traces ข้าม service + Tempo + Loki | debug distributed |
| DB scaling | pgbouncer + read replica for report/list | from 6×20 pool single-DB SPOF |
| Strangler-fig | **Discipline only** — no production users to protect | dual-write/parallel-run skipped where it adds cost without value |

References: `../guard-dispatch/v2-audit/05-recommendations.md` §5.2 (per-service), §5.4 (tech upgrades).

---

## Service map (target)

```
pguard/
├── apps/
│   ├── web-admin/         Next.js 16 App Router, TypeScript strict
│   ├── mobile/            Flutter + Riverpod 2.x codegen
│   └── design-tokens/     tokens.css + tokens.dart + tokens.ts (from Claude Design output)
├── services/
│   ├── api-gateway/       Rust + Axum — JWT validation at edge, rate limit, route
│   ├── identity/          (split from v1 auth) — auth-core, sessions, RBAC
│   ├── profile/           (split from v1 auth) — guard/customer profiles, documents
│   ├── otp/               (split from v1 auth) — OTP, SMS, phone verification
│   ├── booking/           (split from v1 booking) — requests, assignments, discovery
│   ├── payment/           (split from v1 booking) — payments, refunds, proration, receipts
│   ├── rating/            (split from v1 booking) — reviews, visibility moderation
│   ├── calling/           (split from v1 booking) — WebRTC signaling, MediaSoup integration
│   ├── presence/          (renamed tracking) — GPS WebSocket, location history
│   ├── notification/      lean, port + reinforced — REST ingress + service-JWT
│   ├── chat/              lean, port + N+1 fix
│   └── mediasoup/         (Node) SFU — service-JWT'd
├── packages/
│   ├── shared-rust/       types, errors, validators, OTel boilerplate
│   ├── shared-events/     JSON Schema event payloads + serde types
│   └── observability/     OTel setup, trace context propagation
├── contracts/
│   ├── openapi/           per-service .yaml — source of truth
│   ├── asyncapi/          NATS event topics
│   └── db/migrations/     per-service folders
├── infra/
│   ├── docker/            per-service Dockerfile.dev + .prod
│   ├── k8s/               base manifests + kustomize overlays
│   ├── terraform/         IaC
│   └── observability/     OTel collector, Tempo, Loki, Prometheus, Grafana
├── tests/
│   ├── e2e/               Playwright (web) + Patrol (mobile)
│   ├── contract/          Pact contract tests
│   └── load/              k6 scripts (baseline from Phase 0.5)
└── tooling/
    └── codegen/           OpenAPI → Rust stubs / Dart / TS clients
```

Per-service domain layering inside each Rust service:
```
services/<svc>/src/
├── main.rs       wiring only
├── api/          thin transport handlers
├── domain/       PURE logic, 100% unit-testable (proration, state machines)
├── repo/         SQLx queries — DB I/O separated from domain
├── events/       emit/subscribe NATS topics
└── models.rs     DTOs
```

---

## NATS topics

Convention: `pguard.events.<bounded_context>.<event_name>` (e.g. `pguard.events.booking.job_accepted`).

Initial topics (expand via `contracts/asyncapi/events.yaml`):
- `pguard.events.booking.job_accepted` · `.declined` · `.cancelled` · `.completed`
- `pguard.events.booking.guard_en_route` · `.arrived`
- `pguard.events.payment.completed` · `.refund_processed`
- `pguard.events.rating.submitted`
- `pguard.events.calling.initiated` · `.accepted` · `.rejected` · `.ended`
- `pguard.events.chat.message_sent`
- `pguard.events.user.compromised` (triggers force-revoke-all)

Event envelope (every event has): `event_id`, `event_type`, `occurred_at`, `correlation_id`, `payload`.

JetStream durable consumers — at-least-once delivery, idempotency keys on consumer side.

---

## Do / Don't rules

### Backend (Rust)

✅ **Do:**
- Use Axum 0.8 route syntax `/{id}` (not `:id`)
- Domain logic in `domain/` (no DB/HTTP imports allowed there)
- Emit events for cross-service state changes — `EventBus::publish()` not direct INSERT
- Service-JWT on internal endpoints
- OpenTelemetry span per request + event handler + DB transaction
- `cargo fmt` + `cargo clippy -D warnings` clean before commit
- Compile-time `query!` for vanilla SQL; runtime `sqlx::query` only for dynamic/cross-crate

❌ **Don't:**
- No `.unwrap()` / `.expect()` in request path (startup-only)
- No direct INSERT into another service's schema (use events or that service's API)
- No `CorsLayer::permissive()` — use `shared::config::build_cors_layer()`
- No raw `format!()` SQL with user input
- No `tokio::spawn` fire-and-forget for state-changing work (use outbox)

### Flutter (mobile)

✅ **Do:**
- Riverpod 2.x with `@riverpod` codegen
- Pure logic in `core/controllers/` — testable without widgets
- WebSocket lifecycle in `core/network/sockets/` (not in screen)
- Use `PGuardHeader` widget (don't copy-paste header markup)
- `FlutterSecureStorage` for tokens + PIN hash; `SharedPreferences` only for non-sensitive prefs

❌ **Don't:**
- No Provider/ChangeNotifier for new features
- No `Timer.periodic` polling for booking/assignment status (use WS)
- No business logic in screen state (countdown math, proration → controllers)
- No god-screens > 800 LOC (extract widgets + controllers)

### Web (Next.js)

✅ **Do:**
- App Router only (no Pages Router)
- TypeScript strict
- Cookie-based auth (httpOnly, Secure, SameSite=Lax) — never localStorage
- All API calls through generated TS client from OpenAPI
- CSRF token on state-changing endpoints

### Data

✅ **Do:**
- Per-service schema ownership — only that service writes
- Cross-service reads via API (or events for derived state)
- Migrations strictly per-service (`contracts/db/migrations/<svc>/`)
- `CREATE INDEX CONCURRENTLY` for new indexes in production-relevant migrations

❌ **Don't:**
- No new foreign keys across service boundaries
- No `SELECT *` in hot paths
- Binary blobs stay in S3, only keys + metadata in Postgres

---

## Phase status

Tracked in `../guard-dispatch/v2-audit/06-migration-plan.md`. Current state:

- ✅ Phase 1 — Audit (7 files in `../guard-dispatch/v2-audit/`)
- 🟡 Phase 1 revisions (9 items) — pending Claude Code execution per `../guard-dispatch/audit-revisions.md`
- ⏳ Phase 0.5 — Performance baseline + PDPA audit + cost baseline
- ⏳ Phase 0 — Stabilize & safety net (tests + security quick-wins + cleanup)
- ⏳ Phase 1 — Decouple notifications (event bus + service-auth)
- ⏳ Phase 2 — Push-based mobile (WS replaces polling)
- ⏳ Phase 3 — Split booking (call → payment → rating → assignment)
- ⏳ Phase 4 — Split auth + Flutter Riverpod migration
- ⏳ Phase 5 — Scale & harden

After Phase 0 cleanup completes inside `guard-dispatch/`, **rename to `pguard/`** (git history preserved). New scaffolding lives here from that point on.

---

## Quickstart (dev)

```bash
# Once scaffold exists:
./tooling/scripts/dev-up.sh
# Brings up: postgres, nats, redis, minio, otel-collector, grafana, tempo, loki
# Plus all service skeletons on healthz routes

# Per-service dev:
cd services/notification && cargo run
cd apps/web-admin && pnpm dev
cd apps/mobile && flutter run
```

---

## Working with this project

- **Skills:** install via `npx skills add thananon/9arm-skills` — see `.claude/INSTALL-SKILLS.md`
- **Agents:** defined in `.claude/agents/` (4 agents — see file for details)
- **Hooks:** `.claude/hooks/` — pre-tool blocks destructive bash; post-edit runs fmt/clippy/dart-analyze automatically
- **Memory:** `.claude/agent-memory/` per-agent knowledge bases

When stuck, reach for v1 audit:
- Architecture questions → `../guard-dispatch/v2-audit/01-current-state.md`
- "Why this pattern?" → `../guard-dispatch/v2-audit/05-recommendations.md`
- "Will this regress?" → `../guard-dispatch/v2-audit/perf-baseline/results.md` (after Phase 0.5)
- "Is this safe?" → `../guard-dispatch/v2-audit/03-security.md` top 15 risks
