#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# pguard v2 — one-shot migrator.
#
# Services do NOT auto-migrate. This applies every per-service migration in
# contracts/db/migrations/<svc>/*.sql to the PRIMARY, in service (alphabetical) +
# numeric (filename) order. The streaming replica picks the DDL up over WAL — only the
# primary is migrated. Per-service schemas are independent (no cross-schema FKs), so the
# cross-service order is irrelevant; within a service, numeric filename order is honored.
#
# Idempotent / re-runnable: a `public._perf_migrations` ledger records applied files and
# already-applied ones are skipped. The ledger row is written only after a file FULLY applies
# (ON_ERROR_STOP), so a re-run after a fully-applied file is a clean no-op. A mid-file failure
# (a DB blip part-way through a non-idempotent file) commits partial DDL without a ledger row →
# the re-run would re-hit the first non-idempotent statement and need manual cleanup; for the
# perf harness the normal path is a single clean apply against a fresh `down -v` DB.
#
#   set -a; source infra/.env.perf; set +a
#   tooling/scripts/migrate.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="${COMPOSE_FILE:-$ROOT/infra/docker/docker-compose.prod.yml}"
PGUSER="${POSTGRES_USER:-pguard}"
PGDB="${POSTGRES_DB:-pguard}"

# `docker compose exec` consumes its stdin — inside a loop that reads a list on stdin it would eat
# the remaining entries. So: collect the file list into an array up front (no process-sub loop),
# and give every NON-apply psql call `</dev/null`. The apply call alone feeds the .sql via stdin.
psql_cmd() { # no stdin
  docker compose -f "$COMPOSE" exec -T postgres \
    psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$PGDB" "$@" </dev/null
}
psql_apply() { # the migration file on stdin
  docker compose -f "$COMPOSE" exec -T postgres \
    psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$PGDB" -q
}

echo "==> ensuring migration ledger (public._perf_migrations)"
psql_cmd -q -c "CREATE TABLE IF NOT EXISTS public._perf_migrations (file text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());"

# Portable array fill (macOS ships bash 3.2 → no `mapfile`). The find output is fully read here,
# before the apply loop, so no `docker exec` ever competes for this stream.
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$ROOT"/contracts/db/migrations -mindepth 2 -maxdepth 2 -name '*.sql' | sort)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "!! no migrations found under $ROOT/contracts/db/migrations — wrong path?" >&2
  exit 1
fi

applied=0
skipped=0
for sql in "${FILES[@]}"; do
  # `key` is a trusted repo path under contracts/db/migrations/<svc>/ (svc + numeric filename,
  # `[a-z0-9_/.]` only — no user input, no quotes), so interpolating it into the SQL is safe.
  # (psql `-c` does NOT reliably interpolate `:'var'`, so a bound var isn't an option for -c here.)
  key="$(basename "$(dirname "$sql")")/$(basename "$sql")"
  if [ -n "$(psql_cmd -tAc "SELECT 1 FROM public._perf_migrations WHERE file = '$key'" | tr -d '[:space:]')" ]; then
    skipped=$((skipped + 1))
    continue
  fi
  echo "  -> applying $key"
  psql_apply < "$sql"
  psql_cmd -q -c "INSERT INTO public._perf_migrations(file) VALUES ('$key');"
  applied=$((applied + 1))
done

echo "==> migrations: $applied applied, $skipped already-applied"
