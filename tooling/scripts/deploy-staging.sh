#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# pguard v2 — one-command staging deploy (run ON the VPS, from the repo root).
#
#   bash tooling/scripts/deploy-staging.sh            # deploy current origin/main
#   bash tooling/scripts/deploy-staging.sh <git-sha>  # deploy / roll back to a specific sha
#
# Replaces the fragile multi-line paste. Encodes the gotchas learned on 2026-06-15:
#  - deploy.yml tags every image with the FULL 40-char git sha (+ :latest) — NOT the short
#    sha. So IMAGE_TAG defaults to `git rev-parse HEAD` (full), never the short form.
#  - secrets (JWT_SECRET / POSTGRES_PASSWORD / TURN_SECRET / …) live in infra/.env.staging
#    (gitignored) and MUST be sourced before `docker compose` can interpolate ${VAR:?}.
#  - migrate.sh reads COMPOSE_FILE as a SINGLE file (`-f "$COMPOSE_FILE"`, no ':'-join), so it
#    is invoked with COMPOSE_FILE=<prod.yml only> — it just execs into the running postgres.
#  - nginx caches upstream IPs at start → force-recreate it after the backends are recreated.
#
# Rollback: pass a previous good sha as $1, re-run. Migrations are additive + idempotent
# (the `public._perf_migrations` ledger skips applied files); a rollback does not undo DDL.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-infra/.env.staging}"
PROD="infra/docker/docker-compose.prod.yml"
STAGING="infra/docker/docker-compose.staging.yml"
FCM_OVERLAY="infra/docker/docker-compose.fcm.yml"
# Firebase service-account JSON (gitignored). When present, FCM push is auto-enabled by layering the
# fcm overlay (mounts the key + flips FCM_DISABLED=false). Absent → push stays off (NoopPusher).
FCM_SECRET="infra/docker/secrets/fcm-service-account.json"
HEALTHZ_URL="${HEALTHZ_URL:-https://pguard.innoveraappcenter.com/healthz}"

if [ -f "$FCM_SECRET" ]; then
  echo "==> FCM service account found → enabling push (overlay $FCM_OVERLAY)"
  dc() { docker compose -f "$PROD" -f "$STAGING" -f "$FCM_OVERLAY" "$@"; }
else
  echo "==> no FCM service account at $FCM_SECRET → push stays DISABLED"
  dc() { docker compose -f "$PROD" -f "$STAGING" "$@"; }
fi

[ -f "$ENV_FILE" ] || { echo "!! secrets file not found: $ENV_FILE" >&2; exit 1; }

echo "==> [1/7] sync repo to origin/main"
git fetch origin
git checkout main
git pull --ff-only

echo "==> [2/7] load secrets from $ENV_FILE"
set -a; source "$ENV_FILE"; set +a

export REGISTRY="${REGISTRY:-ghcr.io}"
export IMAGE_PREFIX="${IMAGE_PREFIX:-weiwutichai/pguard}"
# deploy.yml tags the FULL git sha; default to current HEAD, or the sha passed as $1.
export IMAGE_TAG="${1:-$(git rev-parse HEAD)}"
echo "    REGISTRY=$REGISTRY  IMAGE_PREFIX=$IMAGE_PREFIX  IMAGE_TAG=$IMAGE_TAG"

echo "==> [3/7] pull images (14 custom + pinned 3rd-party)"
dc pull

echo "==> [4/7] up -d --remove-orphans"
dc up -d --remove-orphans

echo "==> [5/7] apply migrations to the primary (idempotent; replica gets DDL via WAL)"
COMPOSE_FILE="$PROD" tooling/scripts/migrate.sh

echo "==> [6/7] force-recreate nginx (refresh cached upstream IPs)"
dc up -d --force-recreate nginx

echo "==> [7/7] status"
dc ps
curl -fsS -o /dev/null -w "edge healthz -> %{http_code}\n" "$HEALTHZ_URL" \
  || echo "!! healthz curl failed (check nginx / api-gateway logs)"
echo "==> deployed IMAGE_TAG=$IMAGE_TAG"
