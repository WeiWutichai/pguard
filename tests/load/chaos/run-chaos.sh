#!/usr/bin/env bash
# Chaos / failure-injection — proves (or honestly disproves) the v2 resilience design on the
# LOCAL prod stack. Five cases (spec §B): NATS outage→outbox drain, replica down, redis down,
# a mid-tier service down (booking), and a WS-proxy backend killed mid-stream.
#
# Tooling = plain `docker stop -t 0` (crash-like SIGKILL; and because the compose policy is
# `restart: unless-stopped`, a manual STOP stays down until we `docker start` it — `docker kill`
# would be auto-resurrected, fighting the test) + curl/psql/k6 probes. No service code is touched.
# A trap restarts every container we stopped, even on early exit/Ctrl-C.
#
# Each case prints a CHAOS_RESULT line (transcribe into CHAOS.md). LOCAL prod stack only.
#   Usage: tests/load/chaos/run-chaos.sh [1|2|3|4|5|all]
set -uo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
NET="${NET:-pguard-prod}"
PFX="${PFX:-pguard-prod}"
GW="http://api-gateway:3000"
WHAT="${1:-all}"
STOPPED=()

restore() {
  for c in "${STOPPED[@]:-}"; do
    [ -n "$c" ] || continue
    echo "  [restore] docker start $c"
    docker start "$c" >/dev/null 2>&1 || true
  done
  STOPPED=()
}
trap 'echo; echo "[trap] restoring stopped containers…"; restore' EXIT INT TERM

down() { echo "  [chaos] STOP $1"; docker stop -t 0 "$1" >/dev/null 2>&1; STOPPED+=("$1"); }
up()   {
  echo "  [chaos] START $1"; docker start "$1" >/dev/null 2>&1
  # Drop $1 from STOPPED by REBUILD (bash-3.2-safe — `${arr[@]/x}` would leave an empty-string
  # element, not remove it).
  local keep=(); local c
  for c in "${STOPPED[@]:-}"; do [ -n "$c" ] && [ "$c" != "$1" ] && keep+=("$c"); done
  STOPPED=("${keep[@]:-}")
}

# curl on the compose network (host can't always reach internal services; the gateway is the
# only published port but we keep everything on-network for uniformity).
cnet() { docker run --rm --network "$NET" curlimages/curl:latest -s "$@" 2>/dev/null; }
psqlp() { docker exec "${PFX}-postgres" psql -U pguard -d pguard -tAc "$1" 2>/dev/null; }
status() { cnet -o /dev/null -w '%{http_code}' "$@"; }

login() { # login <identifier> <password> → echoes access_token
  cnet -X POST "$GW/v1/auth/login" -H 'Content-Type: application/json' \
    -d "{\"identifier\":\"$1\",\"password\":\"$2\"}" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

wait_healthy() { # wait_healthy <container> <max_s>
  local c="$1" max="${2:-40}" i=0
  while [ $i -lt "$max" ]; do
    local st; st="$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo none)"
    [ "$st" = "healthy" ] && { echo "  [ok] $c healthy (${i}s)"; return 0; }
    if [ "$st" = "none" ]; then docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null | grep -q true && { echo "  [ok] $c running (no healthcheck, ${i}s)"; return 0; }; fi
    sleep 1; i=$((i+1))
  done
  echo "  [warn] $c not healthy after ${max}s"; return 1
}

# ─────────────────────────────────────────────────────────────────────────────
case1_nats() {
  echo "═══ CASE 1 — NATS outage → outbox backs up, then drains (at-least-once) ═══"
  local g; g="$(login 0810000001 Password123!)"
  [ -n "$g" ] || { echo "  CHAOS_RESULT case=nats status=SETUP_FAIL reason=no_guard_token"; return; }

  # An action that ENQUEUES an outbox row: guard accepts a `requested` booking (→ job_accepted).
  pick_requested() { psqlp "select id from booking.bookings where status='requested' order by created_at desc limit 1 offset ${1:-0};"; }

  local base_pending; base_pending="$(psqlp "select count(*) from booking.outbox where published_at is null;")"
  echo "  baseline pending(outbox.published_at IS NULL)=$base_pending"

  down "${PFX}-nats"; sleep 2

  # Accept a requested booking while NATS is DOWN — the business tx must still commit (outbox
  # decouples it from NATS); the relay just can't publish yet.
  local accepted_code="" bid=""
  for off in 0 1 2 3 4; do
    bid="$(pick_requested "$off")"; [ -n "$bid" ] || continue
    accepted_code="$(status -X POST "$GW/v1/bookings/$bid/accept" -H "Authorization: Bearer $g")"
    [ "$accepted_code" = "200" ] || [ "$accepted_code" = "201" ] && break
  done
  echo "  accept (NATS down) booking=$bid http=$accepted_code"
  sleep 3
  local pending_down; pending_down="$(psqlp "select count(*) from booking.outbox where published_at is null;")"
  echo "  pending WHILE nats down=$pending_down (expect > baseline if accept enqueued)"
  sleep 5
  local pending_still; pending_still="$(psqlp "select count(*) from booking.outbox where published_at is null;")"
  echo "  pending after 5s more (still down)=$pending_still (expect unchanged — relay can't publish)"

  up "${PFX}-nats"; wait_healthy "${PFX}-nats" 40

  # Poll for the relay to drain (publish) the backlog once NATS is back.
  local drained="NO" i=0
  while [ $i -lt 40 ]; do
    local p; p="$(psqlp "select count(*) from booking.outbox where published_at is null;")"
    if [ "${p:-1}" -le "${base_pending:-0}" ]; then drained="YES (${i}s)"; break; fi
    sleep 2; i=$((i+2))
  done
  local final_pending; final_pending="$(psqlp "select count(*) from booking.outbox where published_at is null;")"
  echo "  CHAOS_RESULT case=nats accept_http=$accepted_code pending_during=$pending_down pending_still=$pending_still drained=$drained final_pending=$final_pending"
}

# ─────────────────────────────────────────────────────────────────────────────
case2_replica() {
  echo "═══ CASE 2 — postgres-replica down → read routing behaviour ═══"
  local c; c="$(login 0820000001 Password123!)"
  local before; before="$(status "$GW/v1/available-guards" -H "Authorization: Bearer $c")"
  echo "  available-guards (replica up) http=$before"
  down "${PFX}-postgres-replica"; sleep 3
  local disc admin
  disc="$(status "$GW/v1/available-guards" -H "Authorization: Bearer $c")"
  echo "  available-guards (replica DOWN) http=$disc"
  # write/primary path should be unaffected (writes go to primary via pgbouncer)
  local write; write="$(status -X POST "$GW/v1/bookings" -H "Authorization: Bearer $c" -H 'Content-Type: application/json' \
    -d '{"address":"chaos","scheduled_at":"2030-01-01T00:00:00Z","hours":2,"guard_count":1}')"
  echo "  booking-create (primary path, replica down) http=$write"
  up "${PFX}-postgres-replica"; wait_healthy "${PFX}-postgres-replica" 60
  sleep 3
  local after; after="$(status "$GW/v1/available-guards" -H "Authorization: Bearer $c")"
  echo "  available-guards (replica recovered) http=$after"
  local verdict="NO_FALLBACK"; [ "$disc" = "200" ] && verdict="FALLBACK_OR_TOLERATED"
  echo "  CHAOS_RESULT case=replica read_replica_up=$before read_replica_down=$disc write_during=$write read_recovered=$after behaviour=$verdict"
}

# ─────────────────────────────────────────────────────────────────────────────
case3_redis() {
  echo "═══ CASE 3 — redis down → up: edge fail-closes while down, SELF-HEALS on recovery (no restart) ═══"
  local c; c="$(login 0820000001 Password123!)"
  [ -n "$c" ] || echo "  (note: could not pre-fetch token)"
  # Readiness reflects redis BEFORE the outage (expect 200).
  local ready_before; ready_before="$(status "$GW/readyz")"
  echo "  gateway /readyz (redis up) http=$ready_before (expect 200)"
  down "${PFX}-redis"; sleep 3
  # Liveness must stay green: /healthz never touches redis, so a redis blip must NOT cause a
  # k8s restart loop (the gateway self-heals — restarting it would be the wrong response).
  local hz; hz="$(status "$GW/healthz")"
  echo "  gateway /healthz (redis down) http=$hz (expect 200 — liveness, process survives)"
  # Readiness must flip to 503 so orchestration SEES the degraded state (the old /healthz hid it).
  local ready_down; ready_down="$(status "$GW/readyz")"
  echo "  gateway /readyz (redis down) http=$ready_down (expect 503 — readiness reflects redis)"
  # Protected route: edge does jti/trv lookups in redis → fail-closed (5xx), never allow.
  local prot; prot="$(status "$GW/v1/auth/me" -H "Authorization: Bearer $c")"
  echo "  protected /v1/auth/me (redis down) http=$prot (expect 5xx — fail-closed)"
  # Public login still works (no edge auth; rate-limit is fail-open).
  local lg; lg="$(status -X POST "$GW/v1/auth/login" -H 'Content-Type: application/json' -d '{"identifier":"0820000001","password":"Password123!"}')"
  echo "  fresh login (redis down) http=$lg"
  up "${PFX}-redis"; wait_healthy "${PFX}-redis" 40
  # NO gateway restart. Give the ConnectionManager a moment to reconnect in the background
  # (bounded backoff, cap ≤2s) — the next protected request must then succeed on its own.
  sleep 4
  local rec; rec="$(status "$GW/v1/auth/me" -H "Authorization: Bearer $c")"
  echo "  protected /v1/auth/me (redis recovered) http=$rec (expect 200 — gateway reconnected, NO restart)"
  local ready_rec; ready_rec="$(status "$GW/readyz")"
  echo "  gateway /readyz (redis recovered) http=$ready_rec (expect 200 — readiness self-healed)"
  # PASS only if: liveness stayed up, edge fail-CLOSED while down, AND it self-healed w/o a restart.
  local verdict="PASS"
  [ "$hz" = "200" ] || verdict="FAIL(liveness)"
  case "$prot" in 5*) ;; *) verdict="FAIL(not-fail-closed:$prot)";; esac
  [ "$rec" = "200" ] || verdict="FAIL(no-self-heal:$rec)"
  echo "  CHAOS_RESULT case=redis gateway_healthz=$hz readyz_down=$ready_down protected_during=$prot login_during=$lg protected_recovered=$rec readyz_recovered=$ready_rec verdict=$verdict"
}

# ─────────────────────────────────────────────────────────────────────────────
case4_booking() {
  echo "═══ CASE 4 — booking (mid-tier) down → gateway 502, no cascade ═══"
  local c; c="$(login 0820000001 Password123!)"
  down "${PFX}-booking"; sleep 3
  local bk disc me prof
  bk="$(status "$GW/v1/bookings/00000000-0000-0000-0000-000000000000" -H "Authorization: Bearer $c")"
  disc="$(status "$GW/v1/available-guards" -H "Authorization: Bearer $c")"
  me="$(status "$GW/v1/auth/me" -H "Authorization: Bearer $c")"
  prof="$(status "$GW/v1/profile/me" -H "Authorization: Bearer $c")"
  echo "  /v1/bookings/{id} (booking down) http=$bk (expect 502)"
  echo "  /v1/available-guards (booking-owned) http=$disc (expect 502)"
  echo "  /v1/auth/me (identity — unrelated) http=$me (expect 200 — NO cascade)"
  echo "  /v1/profile/me (profile — unrelated) http=$prof (expect 200 — NO cascade)"
  up "${PFX}-booking"; wait_healthy "${PFX}-booking" 60
  sleep 2
  local rec; rec="$(status "$GW/v1/bookings/00000000-0000-0000-0000-000000000000" -H "Authorization: Bearer $c")"
  echo "  /v1/bookings/{id} (recovered) http=$rec (expect 404 — service back, id absent)"
  local cascade="NONE"; { [ "$me" = "200" ] && [ "$prof" = "200" ]; } || cascade="DETECTED"
  echo "  CHAOS_RESULT case=booking booking_down_502=$bk discovery=$disc identity=$me profile=$prof cascade=$cascade recovered=$rec"
}

# ─────────────────────────────────────────────────────────────────────────────
case5_ws() {
  echo "═══ CASE 5 — WS-proxy backend (presence) killed mid-stream → client Close + reconnect ═══"
  local out logf="/tmp/load-out/chaos-ws1.log"; mkdir -p /tmp/load-out
  # Observer connects through the GATEWAY (/v1/ws/track — the real client path), streams 20s.
  ( docker run --rm --network "$NET" -v "$REPO:/repo:ro" -e BASE_URL="$GW" \
      -e WS_URL="ws://api-gateway:3000/v1/ws/track" -e HOLD=20s \
      grafana/k6:latest run --no-color --quiet /repo/tests/load/chaos/ws-observer.js > "$logf" 2>&1 ) &
  local obspid=$!
  sleep 7   # let it open + accumulate acks
  down "${PFX}-presence"   # kill the BACKEND mid-stream
  wait "$obspid" 2>/dev/null
  local cut; cut="$(grep '^CHAOS_WS' "$logf" || echo 'CHAOS_WS (no line)')"
  echo "  during-cut: $cut"
  up "${PFX}-presence"; wait_healthy "${PFX}-presence" 60; sleep 2
  # Reconnect proof: a fresh observer must open again.
  local logf2="/tmp/load-out/chaos-ws2.log"
  docker run --rm --network "$NET" -v "$REPO:/repo:ro" -e BASE_URL="$GW" \
    -e WS_URL="ws://api-gateway:3000/v1/ws/track" -e HOLD=6s \
    grafana/k6:latest run --no-color --quiet /repo/tests/load/chaos/ws-observer.js > "$logf2" 2>&1
  local recon; recon="$(grep '^CHAOS_WS' "$logf2" || echo 'CHAOS_WS (no line)')"
  echo "  after-recovery: $recon"
  echo "  CHAOS_RESULT case=ws_backend_kill during=[$cut] reconnect=[$recon]"
}

[ "$WHAT" = "1" ] || [ "$WHAT" = "all" ] && case1_nats
[ "$WHAT" = "2" ] || [ "$WHAT" = "all" ] && case2_replica
[ "$WHAT" = "3" ] || [ "$WHAT" = "all" ] && case3_redis
[ "$WHAT" = "4" ] || [ "$WHAT" = "all" ] && case4_booking
[ "$WHAT" = "5" ] || [ "$WHAT" = "all" ] && case5_ws
echo "Done. Transcribe CHAOS_RESULT lines into tests/load/CHAOS.md."
