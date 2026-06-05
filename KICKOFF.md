# KICKOFF — pguard (v2)

> **Start here.** Single entry point for Claude Code to begin building pguard.
> Read this → then `CLAUDE.md` (architecture + v1 reference rule) → then `PROGRESS.md`
> (granular task state). Date: 2026-06-04.

---

## 0. The setup (read first)

- **pguard/** (this repo) = the **new v2** we are building. Fresh, clean implementation.
- **../guard-dispatch/** = the **old v1**. **Read-only reference.** Never copy its code
  in, never edit it. Read it to audit, measure, and **port logic into v2 — improving as
  you go.** (Full rule: `CLAUDE.md` → "Relationship to v1".)
- To work with both: open/mount the two folders **side by side**.

## 1. What's already done ✅

- **Audit (Phase 1):** `v1-audit/00–06` + role matrix (`docs/ROLE_MATRIX.md`, `docs/reviews/*.html`).
- **Phase 0.5 audit (B2–B4):** `v1-audit/07-pdpa.md` (PDPA gaps + 9 risks), `v1-audit/cost-baseline.md`, overview updated.
- **Perf-baseline harness (B1):** `v1-audit/perf-baseline/` — 6 k6 scripts + `seed.sql` + README, **validated**. Numbers not captured yet (needs the v1 stack running — see §3).
- **Design:** 40 hi-fi HTML screens + `Design System.html` + `Coverage Matrix.html` in `redesign-pguard/project/pguard/`, plus an interactive **Review Console.html**.
- **Process:** `PROGRESS.md` is the single source of truth; update it at the end of every task (rule in `CLAUDE.md` → "Progress tracking").

## 2. Kickoff — build v2 (do these in order)

Strangler-fig is **discipline only** (no production users — see CLAUDE.md). So the kickoff
is to **scaffold v2 fresh and port from v1**, using the audit + baseline as guardrails.

1. **Scaffold the monorepo** per `CLAUDE.md` → "Service map": `apps/ services/ packages/ contracts/ infra/ tests/ tooling/`. Stub each Rust service on a `/healthz` route.
2. **Contracts first:** write `contracts/openapi/*.yaml` (source of truth) for the first slice, then wire `tooling/codegen` (OpenAPI → Rust stubs / Dart / TS).
3. **`infra/docker` + `dev-up.sh`:** bring up postgres, nats, redis, minio, otel-collector, grafana, tempo, loki (per CLAUDE.md Quickstart).
4. **First vertical slice — notification service (Phase 1):** lean port from v1 + reinforce (event bus + service-JWT). Port logic from `../guard-dispatch/services/notification/`.
5. Continue the phase order in `PROGRESS.md` (push-based mobile → split booking → split auth → scale).

**Carry these v1 findings as v2 acceptance criteria (must not reproduce):**
- Role mismatches #1–3 (`docs/reviews/frontend-backend-permission-mismatch.html`) — build correct role gating into v2 from the start (chat `actingRole`, `available_guards` customer-only, explicit payment role check).
- PDPA 🔴 criticals (`v1-audit/07-pdpa.md`): data-export + erasure endpoints, in-app privacy policy, **GPS `location_history` retention** (v1 never implemented it).

## 3. Optional anytime — capture the perf baseline (needs Docker)

Only to fill `v1-audit/perf-baseline/results.md` with real numbers (the "must not regress
+20%" gate). Runs against **v1 in guard-dispatch**, not pguard:

```bash
cd ../guard-dispatch && docker compose up -d
cd ../pguard/v1-audit/perf-baseline/scripts
docker compose -f ../../../../guard-dispatch/docker-compose.yml exec -T postgres-db \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < seed.sql
export BASE_URL=http://localhost:8080 WS_URL=ws://localhost:8080
k6 run booking-create.js   # …then the rest per perf-baseline/README.md
```
Skip for now if you don't want Docker — the gate only bites once you start refactoring.

## 4. Rules of engagement

- Update `PROGRESS.md` (tick + Completed-log row) at the **end of every task** — Definition of Done is in that file.
- Never copy v1 code into pguard; never edit `../guard-dispatch/`.
- Follow the Do/Don't in `CLAUDE.md` (Axum 0.8 `/{id}`, domain logic pure, events not cross-schema writes, no `.unwrap()` in request path, etc.).
- UI work → tell the user to reload `redesign-pguard/project/pguard/Review Console.html`.

---

## Paste this into Claude Code (opened in pguard/, with ../guard-dispatch/ also accessible)

```
Read KICKOFF.md, then CLAUDE.md, then PROGRESS.md.
guard-dispatch is the v1 read-only reference; pguard is the v2 we build.
Start the kickoff: scaffold the v2 monorepo per the Service map (§2 step 1),
stub each service on /healthz, and propose the first OpenAPI contract slice.
Update PROGRESS.md as you complete each step. Do not modify ../guard-dispatch/.
```
