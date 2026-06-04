#!/usr/bin/env bash
# pguard v2 scaffold stub — local dev bring-up.
# See CLAUDE.md "Quickstart (dev)". Mirrors: ./tooling/scripts/dev-up.sh
# Brings up infra (postgres, nats, redis, minio, otel-collector, grafana, tempo, loki).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT}/infra/docker/docker-compose.yml"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "ERROR: compose file not found: ${COMPOSE_FILE}" >&2
  echo "       (infra scaffold not present yet — see CLAUDE.md Service map → infra/docker/)" >&2
  exit 1
fi

echo "==> Starting pguard dev infra (network: pguard-dev)"
docker compose -f "${COMPOSE_FILE}" up -d

cat <<'EOF'

==> Infra is up. Next steps (see CLAUDE.md "Quickstart (dev)"):

  # Per-service backend (Rust + Axum):
  cd services/notification && cargo run     # repeat per service: identity, profile, otp,
                                            # booking, payment, rating, calling, presence, chat, api-gateway

  # Web admin (Next.js 16):
  cd apps/web-admin && pnpm dev

  # Mobile (Flutter + Riverpod 2.x):
  cd apps/mobile && flutter run

  # Tear down infra when done:
  ./tooling/scripts/dev-down.sh
EOF
