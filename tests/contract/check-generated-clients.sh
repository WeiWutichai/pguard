#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Consumer-side contract guard: the committed web-admin TS client MUST be in sync with the OpenAPI
# specs that generated it. We regenerate it from contracts/openapi/*.yaml and fail if anything
# changed — i.e. someone edited a contract but forgot to `pnpm gen:api` (consumer drift: the client
# the web-admin builds against would expect a shape the contract no longer describes).
#
# This needs only the web-admin toolchain (pnpm + openapi-typescript) — NOT the live stack. The CI
# job runs it as its own step before bringing the stack up.
#
#   tests/contract/check-generated-clients.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"
WEB_ADMIN="${REPO_ROOT}/apps/web-admin"
GENERATED="src/api/generated" # relative to WEB_ADMIN

cd "$WEB_ADMIN"

echo "==> installing web-admin deps (frozen)"
pnpm install --frozen-lockfile

echo "==> regenerating the TS client from contracts/openapi (pnpm gen:api)"
pnpm gen:api

echo "==> checking the regenerated client matches what is committed"
# `git diff --exit-code` catches modified tracked files…
if ! git -C "$REPO_ROOT" diff --exit-code -- "apps/web-admin/${GENERATED}"; then
  echo "!! Generated web-admin client is STALE vs contracts/openapi/*.yaml." >&2
  echo "!! A contract changed without regenerating the client. Run: (cd apps/web-admin && pnpm gen:api)" >&2
  exit 1
fi
# …and `git status --porcelain` also catches a newly-added (untracked) generated file.
if [ -n "$(git -C "$REPO_ROOT" status --porcelain -- "apps/web-admin/${GENERATED}")" ]; then
  echo "!! Generated web-admin client has untracked changes vs contracts/openapi/*.yaml." >&2
  exit 1
fi

echo "==> generated client is up to date with the contracts ✓"
