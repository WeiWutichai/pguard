#!/usr/bin/env bash
# pguard v2 scaffold stub — code generation entrypoint.
# OpenAPI 3.1 (contracts/openapi) + AsyncAPI (contracts/asyncapi) are the source of truth.
# All targets below are TODO placeholders: this script is SAFE to run and does nothing
# destructive yet. See tooling/codegen/README.md and CLAUDE.md "API contracts".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPENAPI_DIR="${ROOT}/contracts/openapi"
ASYNCAPI_DIR="${ROOT}/contracts/asyncapi"

echo "==> pguard codegen"
echo "    OpenAPI specs:  ${OPENAPI_DIR}"
echo "    AsyncAPI specs: ${ASYNCAPI_DIR}"

# --- Target: Rust types + Axum handler stubs -> packages/shared-rust/src/generated/ ---
echo "TODO [rust-handlers]: generate Rust types + Axum stubs into packages/shared-rust/src/generated/"
echo "                      (e.g. openapi-generator rust-axum / progenitor — pin version in README)"

# --- Target: Rust event serde types -> packages/shared-events/src/generated/ ---
echo "TODO [rust-events]:   generate serde event types from contracts/asyncapi into packages/shared-events/src/generated/"

# --- Target: Dart client -> apps/mobile/lib/api/generated/ ---
echo "TODO [dart-client]:   generate Dart client into apps/mobile/lib/api/generated/"
echo "                      (e.g. openapi-generator dart-dio)"

# --- Target: TS client -> apps/web-admin/src/api/generated/ (IMPLEMENTED) ---
# openapi-typescript emits per-spec `paths`/`components` types; the web-admin `lib/api.ts`
# pairs them with `openapi-fetch` at runtime. Run from the app so its pinned dev dep is used.
WEB_ADMIN="${ROOT}/apps/web-admin"
if [ -d "${WEB_ADMIN}/node_modules/openapi-typescript" ]; then
  echo "==> [ts-client] generating web-admin TS types (identity, profile, rating, payment, booking, presence)"
  ( cd "${WEB_ADMIN}" && pnpm gen:api )
else
  echo "TODO [ts-client]: run 'pnpm install' in apps/web-admin first, then 'pnpm gen:api'"
  echo "                  (openapi-typescript → src/api/generated/{identity,profile,rating,payment,booking,presence}.ts; openapi-fetch wraps them in lib/api.ts)"
fi

echo "==> Done (placeholders only — no files written). Wire targets per tooling/codegen/README.md."
