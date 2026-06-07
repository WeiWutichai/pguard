#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# pguard v2 — bring up the REAL stack for e2e, migrate, and seed.
#
# Reuses the perf harness (migrate.sh + seed-v2.sql) and the prod compose, plus the e2e override
# (infra/docker/docker-compose.e2e.yml): SMS disabled (deterministic OTP path) and the two
# gateway-gapped services — rating (:3007) / presence (:3009) — published so the host web-admin can
# reach them directly for the reviews + map pages.
#
# Idempotent: re-running re-applies only new migrations (ledger) and re-seeds (seed-v2 upserts).
#
#   tooling/scripts/e2e-stack-up.sh           # up + migrate + seed
#   PGUARD_E2E_ENV_FILE=infra/.env.e2e ...    # override the env file
#
# Tear down with:  docker compose --env-file infra/.env.e2e \
#   -f infra/docker/docker-compose.prod.yml -f infra/docker/docker-compose.e2e.yml down -v
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ENV_FILE="${PGUARD_E2E_ENV_FILE:-infra/.env.e2e}"
PROD="infra/docker/docker-compose.prod.yml"
OVERRIDE="infra/docker/docker-compose.e2e.yml"
PROJECT="pguard-prod" # compose `name:` → container prefix pguard-prod-*

# The happy-path e2e does not exercise calling/chat/mediasoup or the observability stack, so we
# bring up only the services the web (and mobile) flows touch — faster build + boot.
SERVICES="postgres postgres-replica pgbouncer redis nats minio \
  api-gateway identity profile otp notification booking payment rating presence"

dc() { docker compose --env-file "$ENV_FILE" -f "$PROD" -f "$OVERRIDE" "$@"; }

echo "==> bringing up the e2e stack (build if needed)"
# shellcheck disable=SC2086
dc up -d --build $SERVICES

echo "==> waiting for core services to report healthy (wait-for-condition, no fixed sleep)"
NEED="postgres api-gateway identity profile otp booking payment rating presence"
deadline=$(( $(date +%s) + 300 ))
while :; do
  pending=""
  for s in $NEED; do
    st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
          "${PROJECT}-${s}" 2>/dev/null || echo missing)"
    [ "$st" = "healthy" ] || pending="$pending ${s}(${st})"
  done
  [ -z "$pending" ] && break
  if [ "$(date +%s)" -gt "$deadline" ]; then
    echo "!! services not healthy in time:$pending" >&2
    dc ps >&2
    exit 1
  fi
  sleep 3
done
echo "==> all core services healthy"

# Export the env so the perf migrator's `docker compose -f prod.yml exec` interpolates the compose's
# required ${VAR:?} secrets (it does not take --env-file itself).
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

echo "==> applying migrations (perf harness migrate.sh)"
COMPOSE_FILE="$PROD" tooling/scripts/migrate.sh

echo "==> seeding (seed-v2.sql)"
dc exec -T postgres psql -q -v ON_ERROR_STOP=1 \
  -U "${POSTGRES_USER:-pguard}" -d "${POSTGRES_DB:-pguard}" \
  < v1-audit/perf-baseline/scripts/seed-v2.sql

echo "==> e2e stack ready"
echo "    gateway   http://localhost:${GATEWAY_PORT:-3000}"
echo "    rating    http://localhost:3007   (gateway-gapped — direct for web-admin reviews)"
echo "    presence  http://localhost:3009   (gateway-gapped — direct for web-admin map)"
echo "    next:     cd tests/e2e && pnpm install && npx playwright install chromium && pnpm test:web"
