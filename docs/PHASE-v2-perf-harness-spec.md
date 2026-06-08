# v2 perf harness — migrate + v2 seed + v2 k6 + reliable boot — work spec

> For Claude Code (Terminal B). The perf-baseline (`v1-audit/perf-baseline/`) was written for
> **v1** (schemas `auth.*`/`tracking.*`, paths `/auth/login/mobile`). v2 uses per-service schemas
> (`identity.*`/`presence.*`/…) behind the gateway `/v1/*`. Make the perf run work on the v2 prod
> stack, AND fix the replica first-boot bug found while bringing it up. Branch off freshly synced
> main. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 14f687c
git worktree add ../pguard-perf -b feat/v2-perf-harness main
cd ../pguard-perf
```

## Scope

### A. Reliable prod-stack boot — fix the replica init (real bug)
On Docker Desktop (macOS) the primary's `/docker-entrypoint-initdb.d/10-replication.sh` did **not** run at initdb (bind-mount race / no exec bit) → no `replicator` role, no slot, no `pg_hba` line → the replica `pg_basebackup` failed and the whole stack hung. Make it robust:
- Bake the replication bootstrap into a **small custom primary image** (`infra/docker/postgres-primary.Dockerfile` `FROM postgres:17`, `COPY` the script into `/docker-entrypoint-initdb.d/` with `chmod +x`) **or** an equally race-free mechanism — don't rely on a bind-mounted host file firing during initdb.
- Verify on a fresh `down -v` + `up` that the replica reaches `streaming` (`pg_stat_replication.state='streaming'`, replica `pg_is_in_recovery()=t`) with **no manual steps**.

### B. Migration application
Services don't auto-migrate. Add a **one-shot migrator** (a compose `migrate` profile/service, or a `tooling/scripts/migrate.sh` that applies `contracts/db/migrations/<svc>/*.sql` in service+numeric order to the primary). Idempotent / re-runnable. Document it in the perf README.

### C. v2 seed
Rewrite `v1-audit/perf-baseline/scripts/seed.sql` (or add `seed-v2.sql`) for **v2 schemas**: `identity.users` (+ approved guard/customer), `profile.guard_profiles`/`customer_profiles`, `presence.guard_locations` (200 online guards w/ GPS near 13.7563,100.5018, fresh `recorded_at`), `booking.service_rates` + sample `guard_requests`, `chat.conversations`/`participants`/`messages` (100 convos for the N+1 read). Deterministic UUIDs, `ON CONFLICT DO NOTHING`. Match the actual column names in the merged migrations.

### D. v2 k6 scripts
Update the k6 scripts to v2: gateway base `http://localhost:3000`, `/v1/*` paths (`/v1/auth/login/mobile`, `/v1/available-guards` or the real discovery path, `/v1/bookings`, `/v1/payments`, `/v1/conversations`, GPS `WS /v1/ws/track`). Confirm each path against `contracts/openapi/*` + the gateway routing — **don't assume v1 paths**. Keep the RPS/VU profiles.

### E. Run + record
Bring up the prod stack (after A/B/C), run the read-heavy + write + auth + GPS-WS scripts through the gateway, and **fill `v1-audit/perf-baseline/results.md`**: the HTTP table, GPS-WS table, and the **C5.3 replica gate** table (available-guards / admin lists / ratings p99 — replica-served — vs primary). Note env (host, image tag, date).

## Definition of Done
- `down -v` → `up` brings the FULL stack (incl. streaming replica) healthy with **no manual SQL** (replica fix verified).
- Migrator applies all migrations cleanly; v2 seed loads against the real schema; k6 scripts hit live v2 endpoints (non-error responses).
- `results.md` filled with real numbers + the C5.3 gate table evaluated (PASS/FAIL vs +20%).
- Update `PROGRESS.md` (tick Phase 0.5 perf-baseline captured + C5.3 gate + the replica-init fix · Completed-log row) · run the review agents (code-reviewer + architecture-guardian on the compose/Dockerfile change) · own PR off main · **don't merge**.

## Reference (read-only)
- `v1-audit/perf-baseline/{README.md,results.md,scripts/*}` (v1 shape — adapt). Migrations: `contracts/db/migrations/*/`. Compose + replica: `infra/docker/docker-compose.prod.yml` + `infra/db/primary-replication-init.sh`. Gateway routing/paths: `services/api-gateway/src/domain/routing.rs` + `contracts/openapi/*`. The C5.3 gate procedure is already written at the bottom of `results.md`.
