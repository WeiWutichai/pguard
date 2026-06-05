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

  # Export traces to the collector (→ Tempo) + scale sampling (C5.1). Unset = logging-only:
  export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
  export OTEL_TRACES_SAMPLER_ARG=1.0        # 0.0–1.0 (default 1.0 = sample all)

  # Per-service backend (Rust + Axum) — each exposes /metrics (Prometheus scrapes it):
  cd services/notification && cargo run     # repeat per service: identity, profile, otp,
                                            # booking, payment, rating, calling, presence, chat, api-gateway

  # Observability UIs: Grafana http://localhost:3030 (dashboard "pguard · service overview")
  #                    Prometheus http://localhost:9090 · Tempo via Grafana Explore
  # api-gateway serves /metrics on its admin port 9100 (not the public 3000); other
  # services serve /metrics on their service port. Restrict /metrics to the monitoring
  # network in prod (k8s NetworkPolicy / firewall) — it is unauthenticated.

  # Web admin (Next.js 16):
  cd apps/web-admin && pnpm dev

  # Mobile (Flutter + Riverpod 2.x):
  cd apps/mobile && flutter run

  # Tear down infra when done:
  ./tooling/scripts/dev-down.sh
EOF
