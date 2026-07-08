# pguard — Architecture Spec

> **Real-time Security Guard Dispatch Platform** (Thai market) — v2 of guard-dispatch
> **State:** v2 rebuild. The v1 system is a **separate, read-only reference** at `../guard-dispatch/`. Audit findings drive the v2 design.

Keep this file ≤ 400 lines. Detailed rationale lives in `../guard-dispatch/v2-audit/` (don't inline it).

---

## Relationship to v1 (`../guard-dispatch/`) — READ THIS

`guard-dispatch` is the **old v1 project**. It is a **reference only** and lives in a
**separate sibling folder** (`../guard-dispatch/`), never inside this repo.

✅ **Do:** read v1 to audit it, measure it (perf baseline), and **port logic into the
clean v2** here — improving as you go. Cite the v1 path when you do (e.g.
`../guard-dispatch/services/booking/src/handlers.rs`).

❌ **Don't:** copy or move v1 source/infra (`services/ frontend/ database/ nginx/
docker-compose*`) into `pguard/`. ❌ Don't edit anything under `../guard-dispatch/`
(it is read-only). pguard re-implements v2 fresh; it does not absorb v1's tree.

To work with both, open/mount the **two folders side by side** — do not merge them.

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
│   └── design-tokens/     tokens.css + tokens.dart + tokens.ts (from Codex Design output)
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

## Progress tracking (READ THIS)

**`PROGRESS.md` (repo root) is the single source of truth for what's done.** At the **end of every task**, before reporting back, Codex MUST:

1. Tick the task's checkbox in `PROGRESS.md` (`[ ]`→`[x]`; use `[~]` if started-but-blocked and note the blocker).
2. Add one row to the **Completed log** table (date · task · what changed · files touched · how it was verified).
3. Only mark `[x]` if the task's Definition of Done is met (built **and** verified — tests/clippy/analyze/diff as applicable).
4. For UI changes: tell the user to reload the **Review Console** (`redesign-pguard/project/pguard/Review Console.html`) to re-check.

The user checks `PROGRESS.md` to see progress — keep it current. The phase list below is the high-level mirror; `PROGRESS.md` holds the granular task state.

## Phase status

High-level mirror of `PROGRESS.md`. Granular tasks + completed log live in `PROGRESS.md`. Current state:

- ✅ Phase 1 — Audit (7 files in `v1-audit/` + `role-access-audit-raw.md`)
- ✅ Phase 1 revisions (9/9 items applied to v1-audit/03,05,00,06)
- ⏳ Phase 0.5 — Performance baseline + PDPA audit + cost baseline (brief in `audit-revisions.md` Part B)
- ⏳ Phase 0 — Stabilize & safety net (tests + security quick-wins + cleanup)
- ⏳ Phase 1 — Decouple notifications (event bus + service-auth)
- ⏳ Phase 2 — Push-based mobile (WS replaces polling)
- ⏳ Phase 3 — Split booking (call → payment → rating → assignment)
- ⏳ Phase 4 — Split auth + Flutter Riverpod migration
- ⏳ Phase 5 — Scale & harden

Phase 0 work happens inside `../guard-dispatch/` (v1 reference). After Phase 0 cleanup completes there, the v1 folder will be renamed to consolidate into pguard. Until then, pguard hosts: planning docs, audit findings, design output (Codex Design), role matrix, and the `.Codex/` environment.

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

- **Skills:** install via `npx skills add thananon/9arm-skills` — see `.Codex/INSTALL-SKILLS.md`
- **Agents:** defined in `.Codex/agents/` (4 agents — see file for details)
- **Hooks:** `.Codex/hooks/` — pre-tool blocks destructive bash; post-edit runs fmt/clippy/dart-analyze automatically
- **Memory:** `.Codex/agent-memory/` per-agent knowledge bases

When stuck, reach for v1 audit (now copied locally):
- Architecture questions → `v1-audit/01-current-state.md`
- "Why this pattern?" → `v1-audit/05-recommendations.md`
- "Will this regress?" → `v1-audit/perf-baseline/results.md` (after Phase 0.5)
- "Is this safe?" → `v1-audit/03-security.md` top 15 risks
- Role permissions → `docs/ROLE_MATRIX.md` (source of truth) + `docs/reviews/*.html` (visual)
- Phase brief → `pguard-brief.md`, audit revisions + Phase 0.5 → `audit-revisions.md`
- Hi-fi design output → `redesign-pguard/project/pguard/` (40 HTML files + Coverage Matrix)

## Imported Claude Cowork project instructions
