#!/usr/bin/env bash
# Hard-delete ONE test account (by phone) on staging so the phone can be re-registered cleanly:
# wipes the user's rows across EVERY service schema (FK-safe, one atomic transaction) AND the
# user's S3 objects (documents + avatar), so nothing stale lingers. Scoped to the single user_id
# the phone resolves to — touches no other account.
#
#   bash tooling/scripts/staging-delete-guard.sh 0863208235
#   bash tooling/scripts/staging-delete-guard.sh 0863208235 --yes   # skip the confirm prompt
#
# NOTE: destructive + staging-only. There is no undo. The DB is one Postgres with per-service
# schemas (no cross-schema FKs), so a single transaction keyed on the phone is safe and complete.
set -euo pipefail

PHONE="${1:?usage: staging-delete-guard.sh <phone> [--yes]}"
if ! [[ "$PHONE" =~ ^[0-9]+$ ]]; then
  echo "!! phone must be digits only (got: $PHONE)" >&2
  exit 1
fi

PSQL=(docker exec -i pguard-prod-postgres psql -U pguard -d pguard)

echo "== current account(s) for phone $PHONE =="
"${PSQL[@]}" -c "SELECT id, role, approval_status, created_at FROM identity.users WHERE phone = '$PHONE';"

UID_=$("${PSQL[@]}" -tAc "SELECT id FROM identity.users WHERE phone = '$PHONE'" | tr -d '[:space:]')
if [ -z "$UID_" ]; then
  echo "(no account for $PHONE — nothing to delete; phone is already free)"
  exit 0
fi

if [ "${2:-}" != "--yes" ]; then
  read -r -p "Hard-delete ALL data + S3 objects for $PHONE (user $UID_)? [y/N] " ans
  [ "$ans" = "y" ] || { echo "aborted."; exit 0; }
fi

# --- 1) S3 objects (documents + avatar) under this user's prefix ---
docker exec pguard-prod-minio sh -c \
  "mc alias set local http://127.0.0.1:9000 \"\$MINIO_ROOT_USER\" \"\$MINIO_ROOT_PASSWORD\" >/dev/null 2>&1; \
   mc rm --recursive --force \"local/pguard/profile/$UID_/\" 2>/dev/null || true"

# --- 2) DB rows across all schemas (FK-safe order; otp is phone-keyed; identity last) ---
SEL="(SELECT id FROM identity.users WHERE phone = '$PHONE')"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -c "
BEGIN;
DELETE FROM chat.attachments          WHERE uploader_id IN $SEL;
DELETE FROM chat.read_receipts         WHERE user_id     IN $SEL;
DELETE FROM chat.messages              WHERE sender_id   IN $SEL;
DELETE FROM chat.participants          WHERE user_id     IN $SEL;
DELETE FROM booking.progress_reports   WHERE guard_id    IN $SEL;
DELETE FROM booking.bookings           WHERE customer_id IN $SEL OR guard_id   IN $SEL;
DELETE FROM payment.payments           WHERE customer_id IN $SEL OR guard_id   IN $SEL;
DELETE FROM rating.guard_reviews       WHERE guard_id    IN $SEL OR customer_id IN $SEL;
DELETE FROM calling.call_logs          WHERE caller_id   IN $SEL OR callee_id  IN $SEL;
DELETE FROM presence.location_history  WHERE user_id     IN $SEL;
DELETE FROM presence.guard_locations   WHERE guard_id    IN $SEL;
DELETE FROM presence.guard_assignments WHERE guard_id    IN $SEL OR customer_id IN $SEL;
DELETE FROM notification.fcm_tokens       WHERE user_id  IN $SEL;
DELETE FROM notification.notification_logs WHERE user_id IN $SEL;
DELETE FROM profile.guard_assignments  WHERE guard_id    IN $SEL OR customer_id IN $SEL;
DELETE FROM profile.document_expiry    WHERE guard_id    IN $SEL;
DELETE FROM profile.guard_profiles     WHERE user_id     IN $SEL;
DELETE FROM profile.customer_profiles  WHERE user_id     IN $SEL;
DELETE FROM otp.otp_codes              WHERE phone = '$PHONE';
DELETE FROM identity.refresh_tokens    WHERE user_id     IN $SEL;
DELETE FROM identity.users             WHERE phone = '$PHONE';
COMMIT;
"

echo "== verify (must be 0) =="
"${PSQL[@]}" -tAc "SELECT count(*) AS users_left FROM identity.users WHERE phone = '$PHONE';"
echo "done — phone $PHONE is free to re-register."
