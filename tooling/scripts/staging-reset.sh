#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# pguard v2 — reset STAGING to a clean slate, keeping only the admin account.
#
#   bash tooling/scripts/staging-reset.sh --dry-run   # show what WOULD go (default)
#   bash tooling/scripts/staging-reset.sh --apply     # actually do it
#
# Run ON the VPS from the repo root. Analysis behind every choice here:
# docs/staging-reset-plan.md (Option B — delete-by-name, never TRUNCATE, never touch DDL).
#
# WHY NOT the obvious approaches:
#  - `DROP SCHEMA … CASCADE` + migrate.sh recreates NOTHING: the ledger lives in
#    public._perf_migrations (outside the dropped schemas) so every file reports
#    "already applied". healthz stays green while every API route 500s.
#  - `docker compose down -v` also destroys the MinIO bucket (created by hand, no code
#    recreates it) and leaves the replica on its old PG_VERSION serving PRE-WIPE data.
#  - Wiping Postgres alone is not enough. Redis OTP locks are keyed by PHONE with a 24h
#    TTL, so a test number stays locked out against an empty database; and the JetStream
#    stream has no max_age, so two consumers with no idempotency ledger
#    (presence-booking-links, profile-booking-links) will resurrect deleted rows on replay.
#    That is why the DB wipe, the NATS reset and FLUSHALL must happen in ONE window.
#
# KEPT (verified present on 2026-08-04): the admin row(s), booking.service_catalog (3 rows —
# create_booking reads base_fee from it), notification.broadcasts, public._perf_migrations.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# PGUARD_ROOT lets the script run from outside the tree (e.g. piped to /tmp on the VPS so the
# checked-out working copy is left untouched); it defaults to the repo this file lives in.
ROOT="${PGUARD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$ROOT"

MODE="${1:---dry-run}"
case "$MODE" in
  --dry-run|--apply) ;;
  *) echo "usage: $0 [--dry-run|--apply]" >&2; exit 2 ;;
esac

ENV_FILE="${ENV_FILE:-infra/.env.staging}"
PROD="infra/docker/docker-compose.prod.yml"
STAGING="infra/docker/docker-compose.staging.yml"
FCM_OVERLAY="infra/docker/secrets/fcm-service-account.json"
BACKUP_DIR="${BACKUP_DIR:-$HOME}"
STAMP="$(date +%Y%m%d-%H%M%S)"

[ -f "$ENV_FILE" ] || { echo "!! secrets file not found: $ENV_FILE" >&2; exit 1; }
set -a; source "$ENV_FILE"; set +a

if [ -f "$FCM_OVERLAY" ]; then
  dc() { docker compose -f "$PROD" -f "$STAGING" -f infra/docker/docker-compose.fcm.yml "$@"; }
else
  dc() { docker compose -f "$PROD" -f "$STAGING" "$@"; }
fi
psql_q() { docker exec -i pguard-prod-postgres psql -U pguard -d pguard -v ON_ERROR_STOP=1 "$@"; }

# Services that write to the DB or consume events. Stopped for the whole window: an access
# token stays valid for 15 minutes and auth never re-checks the DB, so a client holding one
# could write rows back in between the DELETE and the COMMIT.
APP_SERVICES="api-gateway identity profile otp notification booking payment rating calling presence chat mediasoup web-admin"

echo "═══ pguard staging reset — mode: $MODE ═══"
echo

# ── 1. Inventory ────────────────────────────────────────────────────────────
echo "==> [1/8] current state"
psql_q -P pager=off -c "
SELECT role, count(*) AS users FROM identity.users GROUP BY role ORDER BY 1;"
psql_q -P pager=off -c "
SELECT id, phone, is_active, approval_status, totp_enabled
  FROM identity.users WHERE role = 'admin' ORDER BY created_at;"

ADMINS=$(psql_q -At -c "SELECT count(*) FROM identity.users WHERE role='admin';")
if [ "$ADMINS" -eq 0 ]; then
  echo "!! ABORT: no admin row — a reset would leave nobody able to log into web-admin," >&2
  echo "   and there is no way to create an admin through the app (registration rejects" >&2
  echo "   the admin role on every path). Create one first." >&2
  exit 1
fi
echo "    admins to keep: $ADMINS"

# The outbox relay must have drained: an unpublished row is a state change no other service
# has seen yet. They all belong to users we are deleting, but a non-zero count means the
# relay is still running — which contradicts the stop below.
UNPUB=$(psql_q -At -c "
SELECT (SELECT count(*) FROM booking.outbox      WHERE published_at IS NULL)
     + (SELECT count(*) FROM payment.outbox      WHERE published_at IS NULL)
     + (SELECT count(*) FROM chat.outbox         WHERE published_at IS NULL)
     + (SELECT count(*) FROM rating.outbox       WHERE published_at IS NULL)
     + (SELECT count(*) FROM calling.outbox      WHERE published_at IS NULL)
     + (SELECT count(*) FROM profile.outbox      WHERE published_at IS NULL)
     + (SELECT count(*) FROM notification.outbox WHERE published_at IS NULL);")
echo "    unpublished outbox rows: $UNPUB"

if [ "$MODE" = "--dry-run" ]; then
  echo
  echo "==> rows that WOULD be deleted"
  psql_q -P pager=off -c "
  SELECT 'identity.users (non-admin)' t, count(*) FROM identity.users WHERE role <> 'admin'
  UNION ALL SELECT 'booking.bookings',        count(*) FROM booking.bookings
  UNION ALL SELECT 'payment.payments',        count(*) FROM payment.payments
  UNION ALL SELECT 'payment.payment_slips',   count(*) FROM payment.payment_slips
  UNION ALL SELECT 'profile.guard_profiles',  count(*) FROM profile.guard_profiles
  UNION ALL SELECT 'profile.customer_profiles',count(*) FROM profile.customer_profiles
  UNION ALL SELECT 'profile.access_audit',    count(*) FROM profile.access_audit
  UNION ALL SELECT 'rating.guard_reviews',    count(*) FROM rating.guard_reviews
  UNION ALL SELECT 'chat.conversations',      count(*) FROM chat.conversations
  UNION ALL SELECT 'chat.messages',           count(*) FROM chat.messages
  UNION ALL SELECT 'presence.location_history',count(*) FROM presence.location_history
  UNION ALL SELECT 'notification.notification_logs', count(*) FROM notification.notification_logs
  UNION ALL SELECT 'otp.otp_codes',           count(*) FROM otp.otp_codes
  UNION ALL SELECT 'calling.call_logs',       count(*) FROM calling.call_logs
  ORDER BY 1;"
  echo
  echo "==> rows that would be KEPT"
  psql_q -P pager=off -c "
  SELECT 'identity.users (admin)' t, count(*) FROM identity.users WHERE role = 'admin'
  UNION ALL SELECT 'booking.service_catalog',  count(*) FROM booking.service_catalog
  UNION ALL SELECT 'notification.broadcasts',  count(*) FROM notification.broadcasts
  UNION ALL SELECT 'public._perf_migrations',  count(*) FROM public._perf_migrations
  ORDER BY 1;"
  echo
  echo "Also cleared on --apply: NATS JetStream (container recreate), Redis (FLUSHALL),"
  echo "MinIO prefixes profile/ booking/ payment/ chat/."
  echo
  echo "Nothing was changed. Re-run with --apply to execute."
  exit 0
fi

# ── 2. Confirm ──────────────────────────────────────────────────────────────
echo
echo "!! This DESTROYS all staging test data (users, bookings, payments, photos, chat)."
echo "!! It is NOT reversible except from the backup taken in the next step."
printf 'Type exactly RESET STAGING to continue: '
read -r CONFIRM
[ "$CONFIRM" = "RESET STAGING" ] || { echo "aborted."; exit 1; }

# ── 3. Backup ───────────────────────────────────────────────────────────────
echo "==> [2/8] backup"
FULL="$BACKUP_DIR/pguard-staging-FULL-$STAMP.dump"
docker exec pguard-prod-postgres pg_dump -U pguard -d pguard -Fc > "$FULL"
echo "    $FULL ($(du -h "$FULL" | cut -f1))"

# ── 4. Stop writers ─────────────────────────────────────────────────────────
echo "==> [3/8] stop application services"
# shellcheck disable=SC2086
dc stop $APP_SERVICES

# ── 5. Postgres ─────────────────────────────────────────────────────────────
echo "==> [4/8] wipe Postgres (single transaction)"
# Every table is named explicitly. No TRUNCATE (it does not follow ON DELETE CASCADE and
# would need every table in one statement anyway), and nothing under public.* is touched,
# so the migration ledger and all DDL survive untouched.
psql_q <<'SQL'
BEGIN;

CREATE TEMP TABLE keep_users AS
  SELECT id FROM identity.users WHERE role = 'admin';

-- chat: children first (the FKs cascade, but explicit order keeps this readable)
DELETE FROM chat.attachments;
DELETE FROM chat.read_receipts;
DELETE FROM chat.messages;
DELETE FROM chat.participants;
DELETE FROM chat.conversations;
DELETE FROM chat.outbox;
DELETE FROM chat.processed_events;

-- booking — KEEP service_catalog (packages + base_fee that create_booking reads)
DELETE FROM booking.progress_reports;
DELETE FROM booking.guard_job_skips;
DELETE FROM booking.bookings;
DELETE FROM booking.outbox;
DELETE FROM booking.processed_events;

-- payment (payment_slips cascades from payments; deleted first for clarity)
DELETE FROM payment.payment_slips;
DELETE FROM payment.payments;
DELETE FROM payment.outbox;
DELETE FROM payment.processed_events;

DELETE FROM rating.outbox;
DELETE FROM rating.guard_reviews;
DELETE FROM calling.outbox;
DELETE FROM calling.call_logs;
DELETE FROM presence.location_history;
DELETE FROM presence.guard_locations;
DELETE FROM presence.guard_assignments;

-- notification — KEEP broadcasts and automation_rules (admin-authored, nothing regenerates them)
DELETE FROM notification.dispatch_recipients;
DELETE FROM notification.notification_logs;
DELETE FROM notification.fcm_tokens;
DELETE FROM notification.outbox;
DELETE FROM notification.processed_events;
-- checkin_reminders (Aug-23 N3 hourly reminder ledger) — the in-progress rows are test-booking
-- derived; clear them so a wiped booking can't be re-reminded. Guarded so this reset still runs
-- against a staging that hasn't been redeployed with migration notification/0007 yet.
DO $$ BEGIN
  IF to_regclass('notification.checkin_reminders') IS NOT NULL THEN
    DELETE FROM notification.checkin_reminders;
  END IF;
END $$;

-- profile — KEEP org_settings. access_audit goes too: it records admin reads of test-user
-- data that is itself being deleted (confirmed with the user 2026-08-04).
DELETE FROM profile.guard_assignments;
DELETE FROM profile.document_expiry;
DELETE FROM profile.guard_profiles;
DELETE FROM profile.customer_profiles;
DELETE FROM profile.outbox;
DELETE FROM profile.access_audit;
-- support_tickets (Aug-23 H1) — test-user submitted; clear. Guarded for pre-redeploy staging
-- (migration profile/0013).
DO $$ BEGIN
  IF to_regclass('profile.support_tickets') IS NOT NULL THEN
    DELETE FROM profile.support_tickets;
  END IF;
END $$;

DELETE FROM otp.otp_codes;

-- identity last: children, then the users themselves, keeping admins
DELETE FROM identity.credential_audit    WHERE user_id NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.user_roles          WHERE user_id NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.refresh_tokens      WHERE user_id NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.totp_recovery_codes WHERE user_id NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.api_tokens          WHERE user_id NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.users               WHERE id      NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.processed_events;

COMMIT;
SQL

# ── 6. NATS ─────────────────────────────────────────────────────────────────
echo "==> [5/8] reset NATS JetStream"
# MUST pair with wiping processed_events above: the stream has no max_age, and
# presence-booking-links / profile-booking-links have no idempotency ledger at all, so a
# replay against the empty DB would recreate guard_assignments rows for deleted bookings.
# `docker restart` does NOT clear the store — the container has to be removed.
dc rm -sfv nats
dc up -d nats

# ── 7. Redis + MinIO ────────────────────────────────────────────────────────
echo "==> [6/8] flush Redis"
# Keys are phone-scoped, not user-scoped: otp_lock:{phone} lives up to 24h and is checked
# BEFORE the OTP is issued, so without this a test number cannot re-register against the
# empty database. user_trv:{user_id} has no TTL at all.
docker exec pguard-prod-redis redis-cli FLUSHALL

echo "==> [7/8] clear MinIO objects"
# Never `mc rb` — the bucket was created by hand and recreating it without
# `mc anonymous set none` would expose guard ID cards publicly.
docker exec pguard-prod-minio sh -c '
  mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1
  for p in profile booking payment chat; do
    mc rm --recursive --force "local/pguard/$p/" >/dev/null 2>&1 || true
  done
  echo "    remaining objects: $(mc ls --recursive local/pguard/ 2>/dev/null | wc -l)"'

# ── 8. Restart + verify ─────────────────────────────────────────────────────
echo "==> [8/8] restart and verify"
dc up -d
sleep 30

psql_q -P pager=off -c "
SELECT 'users total' t, count(*) FROM identity.users
UNION ALL SELECT 'users non-admin', count(*) FROM identity.users WHERE role <> 'admin'
UNION ALL SELECT 'bookings',        count(*) FROM booking.bookings
UNION ALL SELECT 'payments',        count(*) FROM payment.payments
UNION ALL SELECT 'guard_profiles',  count(*) FROM profile.guard_profiles
UNION ALL SELECT 'otp_codes',       count(*) FROM otp.otp_codes
UNION ALL SELECT '-- KEPT service_catalog', count(*) FROM booking.service_catalog
UNION ALL SELECT '-- KEPT broadcasts',      count(*) FROM notification.broadcasts
UNION ALL SELECT '-- KEPT migrations',      count(*) FROM public._perf_migrations
ORDER BY 1;"

dc ps --format '{{.Name}}\t{{.Status}}' | grep -v Up || true
curl -fsS -o /dev/null -w "edge healthz -> %{http_code}\n" \
  "https://pguard.innoveraappcenter.com/healthz" || echo "!! healthz failed"

echo
echo "═══ done. backup: $FULL ═══"
echo "Remaining manual step: clear app data on the test phones — the tokens and PIN in"
echo "FlutterSecureStorage outlive the server wipe, so the app still looks logged in."
echo "  adb -s <serial> shell pm clear app.pguard.mobile"
