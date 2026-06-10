#!/usr/bin/env bash
# pguard v2 — code generation entrypoint. OpenAPI 3.1 (contracts/openapi) + AsyncAPI
# (contracts/asyncapi) are the source of truth; generated output is committed (CI stale-checks
# regenerate + `git diff --exit-code` it — TS via tests/contract/check-generated-clients.sh,
# Dart + Rust events via tests/contract/check-generated-codegen.sh).
#
# Idempotent: re-running on unchanged contracts produces byte-identical output (every generator
# here is pinned + deterministic). Each target checks its toolchain and SKIPs (loudly) if absent,
# so a partial environment still runs the targets it can. See tooling/codegen/README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEGEN="${ROOT}/tooling/codegen"
OPENAPI_DIR="${ROOT}/contracts/openapi"
ASYNCAPI_DIR="${ROOT}/contracts/asyncapi"

# Per-service OpenAPI specs (the Dart + TS targets iterate these).
SPECS=(booking calling chat identity notification otp payment presence profile rating)

echo "==> pguard codegen"
echo "    OpenAPI specs:  ${OPENAPI_DIR}"
echo "    AsyncAPI specs: ${ASYNCAPI_DIR}"

# ── Target: TS client → apps/web-admin/src/api/generated/ (openapi-typescript + openapi-fetch) ──
WEB_ADMIN="${ROOT}/apps/web-admin"
if [ -d "${WEB_ADMIN}/node_modules/openapi-typescript" ]; then
  echo "==> [ts-client] regenerating web-admin TS types (pnpm gen:api)"
  ( cd "${WEB_ADMIN}" && pnpm gen:api )
else
  echo "SKIPPED [ts-client]: run 'pnpm install' in apps/web-admin first (openapi-typescript)."
fi

# ── Target: Dart client → apps/mobile/lib/api/generated/<svc>/ (openapi-generator dart-dio) ──
# Pinned: tooling/codegen/package.json (CLI 2.15.3) + openapitools.json (generator 7.14.0).
# --skip-validate-spec: our 3.1 specs omit the OPTIONAL info.license.identifier/url that
# generator 7.14 validates over-strictly; the specs are valid OpenAPI 3.1.
DART_OUT="${ROOT}/apps/mobile/lib/api/generated"
OG_CLI="${CODEGEN}/node_modules/.bin/openapi-generator-cli"
if [ -x "${OG_CLI}" ] && command -v java >/dev/null 2>&1; then
  echo "==> [dart-client] regenerating mobile Dart packages (openapi-generator dart-dio)"
  for svc in "${SPECS[@]}"; do
    echo "    -> ${svc}"
    rm -rf "${DART_OUT}/${svc}"
    ( cd "${CODEGEN}" && "${OG_CLI}" generate \
        -g dart-dio \
        -i "${OPENAPI_DIR}/${svc}.yaml" \
        -o "${DART_OUT}/${svc}" \
        --skip-validate-spec \
        --global-property=apiTests=false,modelTests=false,apiDocs=false,modelDocs=false \
        --additional-properties=pubName=pguard_"${svc}"_api \
        >/dev/null )
  done
else
  echo "SKIPPED [dart-client]: need Java 11+ and 'pnpm install' in tooling/codegen (openapi-generator-cli)."
fi

# ── Target: Rust event serde types → packages/shared-events/src/generated/events.rs ──
# Small in-repo generator (python3 + PyYAML). Output is rustfmt-clean by construction.
if python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "==> [rust-events] regenerating shared-events payload types (gen_rust_events.py)"
  python3 "${CODEGEN}/gen_rust_events.py"
else
  echo "SKIPPED [rust-events]: pip install -r tooling/codegen/requirements.txt (PyYAML)."
fi

# ── Target: Rust types + Axum handler stubs → packages/shared-rust/src/generated/ ──
# SKIPPED by decision (not a TODO): the 11 services are hand-written + complete, and the contract
# tests (PR #32) already verify each provider against its OpenAPI spec at runtime. Generating
# trait/handler stubs now would be pure churn against finished code with no consumer. Revisit when
# a NEW service is scaffolded from a spec. See tooling/codegen/README.md → "Skipped: Axum stubs".
echo "SKIPPED [rust-handlers]: services hand-written + contract-tested; stub gen = churn (see README)."

echo "==> codegen done."
