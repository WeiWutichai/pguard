#!/usr/bin/env bash
# Ceiling sweep — ramp each hot path until it breaks, on the LOCAL prod stack.
#
# Runs k6 as a container ON the `pguard-prod` compose network (so it reaches the gateway at
# api-gateway:3000 and presence directly at presence:3009 by Docker DNS — no host ports needed),
# with the repo root mounted read-only so the load scripts' relative import of the baseline
# `_common.js` resolves. Sweeps increasing offered load per endpoint and prints one CEILING_RESULT
# line per step; the ladder stops early once an endpoint breaches the knee (err>2% or p99>KNEE_MS),
# so the LAST clean step ≈ the ceiling. Transcribe the printed lines into RESULTS.md.
#
# NEVER point this at staging/production — it is a breaking-point test. Local stack only.
#
# Usage:
#   tests/load/run-ceiling.sh            # full sweep (http ladders + ws ladder + mixed)
#   tests/load/run-ceiling.sh http       # http ladders only
#   tests/load/run-ceiling.sh ws         # ws ladder only
#   tests/load/run-ceiling.sh mixed      # mixed workload only
#   NETWORK=pguard-prod STEP_DUR=20s KNEE_MS=2000 tests/load/run-ceiling.sh
set -uo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
NETWORK="${NETWORK:-pguard-prod}"
GATEWAY="${GATEWAY:-http://api-gateway:3000}"
PRESENCE_WS="${PRESENCE_WS:-ws://presence:3009}"
STEP_DUR="${STEP_DUR:-20s}"
WS_HOLD="${WS_HOLD:-25s}"
KNEE_MS="${KNEE_MS:-2000}"     # p99 above this = past the knee
ERR_KNEE="${ERR_KNEE:-2.0}"    # err% above this = past the knee
K6_IMAGE="${K6_IMAGE:-grafana/k6:latest}"
WHAT="${1:-all}"

k6run() { # k6run <script-rel-path> <env...>
  local script="$1"; shift
  local envs=(); for kv in "$@"; do envs+=(-e "$kv"); done
  docker run --rm --network "$NETWORK" -v "$REPO:/repo:ro" \
    -e "BASE_URL=$GATEWAY" -e "PRESENCE_WS=$PRESENCE_WS" "${envs[@]}" \
    "$K6_IMAGE" run --no-color --quiet "/repo/$script" 2>&1
}

TARGET="${TARGET:-gateway}"  # gateway (edge, rate-limited) | direct (service, true backend ceiling)

http_ladder() { # http_ladder <endpoint> <rps...>
  local ep="$1"; shift
  echo "═══ HTTP ladder: $ep [target=$TARGET] (step=$STEP_DUR, knee p99>${KNEE_MS}ms or err>${ERR_KNEE}%) ═══"
  for rps in "$@"; do
    local out line p99 err
    out="$(k6run tests/load/ceiling-http.js "ENDPOINT=$ep" "RPS=$rps" "DURATION=$STEP_DUR" "TARGET=$TARGET")"
    line="$(echo "$out" | grep '^CEILING_RESULT' || true)"
    if [ -z "$line" ]; then echo "  [rps=$rps] NO RESULT — k6 error:"; echo "$out" | tail -5; break; fi
    echo "  $line"
    p99="$(echo "$line" | sed -n 's/.*p99_ms=\([0-9.]*\).*/\1/p')"
    err="$(echo "$line" | sed -n 's/.*err_rate=\([0-9.]*\)%.*/\1/p')"
    if awk "BEGIN{exit !($p99>$KNEE_MS || $err>$ERR_KNEE)}"; then
      echo "  → KNEE at rps=$rps (p99=${p99}ms err=${err}%). Ceiling ≈ previous clean step."
      break
    fi
    sleep 6
  done
  echo
}

ws_ladder() {
  echo "═══ WS ladder: /ws/track (hold=$WS_HOLD) ═══"
  for vus in "$@"; do
    local out line fail
    out="$(k6run tests/load/ceiling-ws.js "STAGE_VUS=$vus" "HOLD=$WS_HOLD")"
    line="$(echo "$out" | grep '^CEILING_WS' || true)"
    if [ -z "$line" ]; then echo "  [vus=$vus] NO RESULT:"; echo "$out" | tail -5; break; fi
    echo "  $line"
    fail="$(echo "$line" | sed -n 's/.*conn_failures=\([0-9]*\).*/\1/p')"
    if awk "BEGIN{exit !($fail > $vus*0.02)}"; then
      echo "  → KNEE at vus=$vus (conn_failures=$fail > 2%). Ceiling ≈ previous clean step."
      break
    fi
    sleep 6
  done
  echo
}

# Portable dispatch (no bash-4 `;;&` — macOS ships bash 3.2).
if [ "$WHAT" = "http" ] || [ "$WHAT" = "all" ]; then
  http_ladder login 5 10 20 40 80
  http_ladder discovery 30 100 200 400 800
  http_ladder booking 50 100 200 400
fi
# `direct` — bypass the gateway rate limit to find the true BACKEND ceiling (Argon2/DB pool).
if [ "$WHAT" = "direct" ]; then
  TARGET=direct
  http_ladder login 10 30 60 120 240
  http_ladder discovery 100 300 600 1000
  http_ladder booking 100 300 600 1000
fi
if [ "$WHAT" = "ws" ] || [ "$WHAT" = "all" ]; then
  ws_ladder 100 300 500 800
fi
if [ "$WHAT" = "mixed" ] || [ "$WHAT" = "all" ]; then
  echo "═══ Mixed workload (busy hour) ═══"
  k6run tests/load/mixed-workload.js "DURATION=${MIX_DUR:-60s}" "MIX_SCALE=${MIX_SCALE:-1}" | grep -E '^MIXED|^  ' || true
fi
echo "Done. Transcribe the CEILING_RESULT / CEILING_WS / MIXED lines into tests/load/RESULTS.md."
