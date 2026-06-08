# Phase 5 — C5.3 DB scaling (pgbouncer + read replica) — work spec

> For Claude Code. Fix the v1 6×20 single-DB SPOF: add **pgbouncer** (transaction pooling)
> + a **read replica** for report/list/discovery reads. Touches `packages/shared-rust` (db
> layer — ripples to all services), so **one backend track only**. Branch off the freshly
> synced main. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 73362fe
git worktree add ../pguard-c53 -b feat/c5.3-db-scaling main
```

## Scope

### A. shared-rust db layer — primary + replica pools
- Extend the db module so `AppState` carries **two pools**: `db` (primary, writes + read-your-write) and `db_read` (replica, read-only). Config: `DATABASE_URL` (primary, via pgbouncer) + `DATABASE_READ_URL` (replica; **fall back to primary** if unset so single-node dev still works).
- Keep pool sizing sane (no more 6×20 explosion now that pgbouncer fronts it).

### B. Route read-heavy queries to the replica
- Point the **list/report/discovery** reads at `db_read`: admin lists (reviews, payments, refunds, customers), `available-guards` discovery, ratings summary, any report endpoints. **Writes and read-after-write stay on the primary.**
- Be careful with replica lag: anything that reads immediately after its own write (e.g. create→return) must use the primary.

### C. infra — pgbouncer + replica
- `infra/docker/docker-compose.prod.yml`: add **pgbouncer** in front of Postgres (services' `DATABASE_URL` → pgbouncer; transaction mode). Add a **read-replica** Postgres (streaming replication or a documented stand-in) + set `DATABASE_READ_URL` to it. pgbouncer config file under `infra/`.
- Keep the network-isolation rule (only gateway publishes host ports).

### D. Re-run the perf baseline (gate)
- After wiring, **re-run B1** (`v1-audit/perf-baseline/`) and fill `results.md`; confirm the regression gate (list/discovery p99 within +20% of the v1 baseline — ideally better with the replica). This step needs a real Docker host — if the daemon is unavailable here, document the exact command + leave results.md ready, like PR #9/#10 did.

## Rules (CLAUDE.md)
- per-service schema ownership unchanged · no `.unwrap()` in request path · `CREATE INDEX CONCURRENTLY` for any new prod index · OTel span per request/tx (C5.1 already wired) · secrets via `${VAR:?}`.

## Definition of Done
- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅
- `db_read` pool wired; list/discovery endpoints read from the replica pool (prove via a routing/unit test or a logged pool tag); writes + read-after-write on primary (test one create→read path stays consistent).
- `docker compose -f infra/docker/docker-compose.prod.yml config` validates with pgbouncer + replica.
- `results.md` updated (or the run command documented if no Docker here).
- Update `PROGRESS.md` (tick + Completed-log row) · run the 3 review agents · own PR off main · don't merge.

## Reference (read-only)
- `v1-audit/05-recommendations.md` §5.4 + `v1-audit/02-issues.md` (the 6×20 SPOF) + `cost-baseline.md` (pgbouncer/replica = the C5.3 cost delta) + CLAUDE.md "DB scaling" decision.
- v1 `../guard-dispatch/` connection-pool setup (the pattern being replaced).
