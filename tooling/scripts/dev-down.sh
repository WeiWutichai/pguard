#!/usr/bin/env bash
# pguard v2 scaffold stub — local dev tear-down.
# See CLAUDE.md "Quickstart (dev)". Stops infra started by dev-up.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT}/infra/docker/docker-compose.yml"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "ERROR: compose file not found: ${COMPOSE_FILE}" >&2
  exit 1
fi

echo "==> Stopping pguard dev infra"
# Pass --volumes to also drop dev data: ./dev-down.sh --volumes
docker compose -f "${COMPOSE_FILE}" down "$@"
