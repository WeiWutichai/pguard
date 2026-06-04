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

# --- Target: TS client -> apps/web-admin/src/api/generated/ ---
echo "TODO [ts-client]:     generate TS client into apps/web-admin/src/api/generated/"
echo "                      (e.g. openapi-typescript + openapi-fetch)"

echo "==> Done (placeholders only — no files written). Wire targets per tooling/codegen/README.md."
