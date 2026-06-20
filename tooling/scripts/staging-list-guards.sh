#!/usr/bin/env bash
# List every guard account on staging with its phone, approval status, and how many of the 6
# credential images are uploaded. READ-ONLY — run on the VPS before re-registering a test phone
# so you can see what already exists (and reuse staging-delete-guard.sh to wipe it first).
#
#   bash tooling/scripts/staging-list-guards.sh
set -euo pipefail

docker exec -i pguard-prod-postgres psql -U pguard -d pguard -c "
SELECT
  u.id,
  u.phone,
  u.approval_status,
  u.created_at,
  (CASE WHEN gp.id_card_key          IS NOT NULL THEN 1 ELSE 0 END
 + CASE WHEN gp.security_license_key IS NOT NULL THEN 1 ELSE 0 END
 + CASE WHEN gp.training_cert_key    IS NOT NULL THEN 1 ELSE 0 END
 + CASE WHEN gp.criminal_check_key   IS NOT NULL THEN 1 ELSE 0 END
 + CASE WHEN gp.driver_license_key   IS NOT NULL THEN 1 ELSE 0 END
 + CASE WHEN gp.passbook_photo_key   IS NOT NULL THEN 1 ELSE 0 END) AS docs_6
FROM identity.users u
LEFT JOIN profile.guard_profiles gp ON gp.user_id = u.id
WHERE u.role = 'guard'
ORDER BY u.created_at DESC;
"
