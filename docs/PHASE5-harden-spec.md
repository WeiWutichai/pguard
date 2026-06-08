# Phase 5 — Scale & harden (work spec, track C)

> For Claude Code. The final backend track. Runs **in parallel with Phase 2 mobile**
> (disjoint footprint). This is **one track, multiple sub-slices** — do them in order,
> each its own review + PR. Several touch shared crates (`observability`, `shared-rust`)
> which ripple across all services, so **don't run two backend agents here at once**
> (sub-agent worktrees within a slice are fine). Don't merge; don't edit `../guard-dispatch/`.

## C5.1 — Observability wiring (do first; foundation)

Scaffolded but not wired (infra has tempo/loki/prometheus/grafana; services have spans).
- `packages/observability`: add the **OTLP exporter** → otel-collector → Tempo; real
  trace sampling config via env. Keep `init_telemetry` idempotent.
- **Trace-context propagation across services** (HTTP headers) **and across NATS** events
  (carry traceparent in the event envelope/headers) so a booking→payment→notification
  flow is one trace.
- Prometheus metrics endpoint per service; basic Grafana dashboard (request rate, p99, error rate, consumer lag).
- Touches: `packages/observability` + every service `main.rs` (shared — serialize).
- DoD: a single end-to-end trace spans ≥3 services in Tempo; metrics scrape green.

## C5.2 — PDPA criticals (close the 🔴 from `v1-audit/07-pdpa.md`)

Highest compliance risk; some are real gaps I found vs v1.
- **GPS `location_history` retention purge** — v1 NEVER implemented it (unbounded sensitive data). Add a scheduled purge (90-day) in the presence service + index for efficient DELETE.
- **`GET /v1/me/data-export`** — aggregate a user's data across identity/profile/booking/payment/rating/chat over service-JWT → one JSON (PDPA §19/§32).
- **`DELETE /v1/me`** — soft-delete + PII redaction, keep minimal audit (PDPA §33).
- **Read-access audit** — log admin GETs of personal data (profiles/docs/GPS/chat) (PDPA §30).
- (Privacy-policy / consent UI → product + mobile track; note the backend consent flags here.)
- DoD: retention job proven on seeded old rows; data-export returns cross-service JSON; erasure redacts PII + blocks re-login; admin read-audit row written.

## C5.3 — DB scaling (fix the 6×20 single-DB SPOF)

- **pgbouncer** in front of Postgres (`infra/`) → services point `DATABASE_URL` at it (transaction pooling).
- **Read replica** for report/list/discovery (admin lists, available-guards, ratings) — a read pool routed to the replica; writes stay on primary. Wire in `shared-rust` db layer.
- DoD: list/report endpoints read from replica (verify via routing/log); pool config documented; perf-baseline re-run shows no p99 regression > +20% (`v1-audit/perf-baseline/`).

## C5.4 — Security sweep (close `v1-audit/03-security.md` top risks not yet covered)

- Confirm every service has the audit-middleware equivalent + JWT validation at edge (gateway already does jti+trv+CSRF).
- nginx/edge: security headers + per-zone rate limits parity with v1 (gateway has tiers — verify coverage incl. swagger/docs gating via `ENABLE_SWAGGER`).
- Secrets: all via env (`${VAR:?}`), no defaults; Docker non-root + stripped binaries (per CLAUDE.md Docker rules).
- DoD: a short `v1-audit/03-security.md`-style checklist, each item ✅ with the file/proof.

## Cross-cutting rules

- CLAUDE.md Do/Don't throughout (Decimal-as-string, no `.unwrap()` in request path, per-service schema, events-not-cross-writes).
- Each sub-slice: `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅ · run the 3 review agents, fix findings · update `PROGRESS.md` (tick + Completed-log row) · its own PR.
- After C5.3, **re-run the B1 perf-baseline** to fill `v1-audit/perf-baseline/results.md` and confirm the regression gate.

## Reference (read-only)

- `v1-audit/05-recommendations.md` §5.4 (tech upgrades) · `v1-audit/03-security.md` (top 15 risks) · `v1-audit/07-pdpa.md` (data inventory + 9 risks) · `v1-audit/cost-baseline.md` (the +30–50% infra delta lands here) · CLAUDE.md "Architecture decisions" (pgbouncer, OTel+Tempo+Loki, token revocation).
