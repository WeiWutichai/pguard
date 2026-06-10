#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Stale-codegen guard for the Dart client + Rust event types (sibling of
# check-generated-clients.sh, which covers the web-admin TS client). Regenerates both committed
# artifacts from the contracts and fails if anything changed — i.e. someone edited a contract (or
# a generator) but forgot to `./tooling/codegen/generate.sh`. That drift would mean the committed
# Dart client / Rust payload types no longer describe the contract they claim to.
#
# Toolchains (the CI job sets these up; pinned for reproducibility):
#   - Dart client : openapi-generator-cli 2.15.3 → generator 7.14.0 (tooling/codegen pnpm pkg) + Java 11+
#   - Rust events : python3 + PyYAML (tooling/codegen/requirements.txt)
# The TS client is intentionally NOT re-checked here (the contract-tests job already does).
#
#   tests/contract/check-generated-codegen.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"
PATHS=("apps/mobile/lib/api/generated" "packages/shared-events/src/generated")

echo "==> installing pinned Dart codegen toolchain (tooling/codegen)"
( cd "${REPO_ROOT}/tooling/codegen" && pnpm install --frozen-lockfile )

echo "==> installing the Rust-events generator deps (PyYAML)"
python3 -m pip install --quiet -r "${REPO_ROOT}/tooling/codegen/requirements.txt"

echo "==> regenerating Dart client + Rust event types from the contracts"
"${REPO_ROOT}/tooling/codegen/generate.sh"

echo "==> checking the regenerated output matches what is committed"
# `git diff --exit-code` catches modified tracked files…
if ! git -C "${REPO_ROOT}" diff --exit-code -- "${PATHS[@]}"; then
  echo "!! Generated Dart/Rust-event code is STALE vs the contracts." >&2
  echo "!! A contract or generator changed without regenerating. Run: ./tooling/codegen/generate.sh" >&2
  exit 1
fi
# …and `git status --porcelain` also catches newly-added (untracked) or deleted generated files.
if [ -n "$(git -C "${REPO_ROOT}" status --porcelain -- "${PATHS[@]}")" ]; then
  echo "!! Generated Dart/Rust-event code has untracked/removed files vs the contracts." >&2
  git -C "${REPO_ROOT}" status --porcelain -- "${PATHS[@]}" >&2
  exit 1
fi

echo "==> generated Dart client + Rust event types are up to date with the contracts ✓"
