#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Bring up the REAL stack for the contract suite. We REUSE the shared e2e harness untouched
# (tooling/scripts/e2e-stack-up.sh → build + migrate + seed-v2), then add the ONE service the
# contract suite needs that the happy-path e2e skips: `chat` (it is not in e2e-stack-up.sh's
# SERVICES list). With chat up, the gateway routes /v1/conversations + /v1/attachments to it.
#
#   tests/contract/stack-up.sh
#
# Tear down (everything, incl. chat) with:
#   docker compose --env-file infra/.env.e2e \
#     -f infra/docker/docker-compose.prod.yml -f infra/docker/docker-compose.e2e.yml down -v
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
cd "$ROOT"

ENV_FILE="${PGUARD_E2E_ENV_FILE:-infra/.env.e2e}"
PROD="infra/docker/docker-compose.prod.yml"
OVERRIDE="infra/docker/docker-compose.e2e.yml"
PROJECT="pguard-prod"

echo "==> bringing up the shared e2e stack (build + migrate + seed)"
tooling/scripts/e2e-stack-up.sh

echo "==> bringing up chat (extra service the contract suite needs; not in the e2e SERVICES list)"
docker compose --env-file "$ENV_FILE" -f "$PROD" -f "$OVERRIDE" up -d --build chat

echo "==> waiting for chat to report healthy"
deadline=$(( $(date +%s) + 180 ))
while :; do
  st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "${PROJECT}-chat" 2>/dev/null || echo missing)"
  [ "$st" = "healthy" ] && { echo "==> chat healthy"; break; }
  [ "$st" = "none" ] && { echo "==> chat has no healthcheck; assuming up"; break; }
  if [ "$(date +%s)" -gt "$deadline" ]; then
    echo "!! chat not healthy in time (st=$st)" >&2
    docker compose --env-file "$ENV_FILE" -f "$PROD" -f "$OVERRIDE" logs --tail 40 chat >&2 || true
    exit 1
  fi
  sleep 3
done

# The object-store bucket. The happy-path e2e never uploads, so e2e-stack-up.sh doesn't create it —
# but the contract suite exercises real photo/attachment uploads (booking check-in + chat attachment),
# which 500 without a bucket. Create it here (idempotent), the same spirit as seeding the DB.
echo "==> ensuring the MinIO object-store bucket exists"
set -a; # shellcheck disable=SC1090
source "$ENV_FILE"; set +a
docker run --rm --network "container:${PROJECT}-minio" --entrypoint sh minio/mc -c \
  "mc alias set m http://localhost:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' >/dev/null 2>&1 && \
   mc mb -p --ignore-existing \"m/${S3_BUCKET:-pguard}\"" \
  || { echo "!! failed to create MinIO bucket ${S3_BUCKET:-pguard}" >&2; exit 1; }

echo "==> contract stack ready (gateway :3000, rating direct :3007, chat via gateway, MinIO bucket ready)"
