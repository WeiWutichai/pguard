#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# pguard — build the staging release APK, version it from git, upload to Drive.
#
#   tooling/scripts/build-apk.sh
#
# Version, with NO pubspec churn and NO per-build commit:
#   - version NAME  = pubspec `version:` (the `0.1.0` part) — the human release line
#   - build NUMBER  = `git rev-list --count HEAD` — monotonic, one per commit
#   - both are passed to `flutter build` via --build-name / --build-number, so the
#     built APK's own versionName/versionCode carry them (visible in Android settings).
# The artifact is renamed `pguard-v<name>+<build>-<shortsha>[-dirty]-<UTCdate>.apk`, so
# every file self-identifies which commit produced it.
#
# Upload: `rclone copy` to a Google Drive remote. Configure it ONCE (browser OAuth),
# rooting the remote at the target Drive FOLDER by id so uploads land there directly:
#     rclone config create pguard-drive drive \
#         root_folder_id 1AKXMRJwzjf-5YaTWwAW0odvt4NZ3cP34 config_is_local false
# Override the target with PGUARD_DRIVE_REMOTE (default pguard-drive:) and PGUARD_DRIVE_DIR
# (default empty — the remote is already rooted at the folder). If the remote isn't
# configured the build still succeeds — it just skips the upload and says so.
#
# Every build appends one row to dist/BUILDS.tsv (local record; dist/ is gitignored).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOBILE="$ROOT/apps/mobile"
DIST="$MOBILE/dist"
API_HOST="${PGUARD_API_HOST:-https://pguard.innoveraappcenter.com}"
DRIVE_REMOTE="${PGUARD_DRIVE_REMOTE:-pguard-drive:}"
DRIVE_DIR="${PGUARD_DRIVE_DIR:-}"

cd "$ROOT"

# ── version ──────────────────────────────────────────────────────────────────
NAME="$(grep '^version:' "$MOBILE/pubspec.yaml" | sed 's/version:[[:space:]]*//;s/+.*//' | tr -d '[:space:]')"
BUILD="$(git rev-list --count HEAD)"
SHA="$(git rev-parse --short HEAD)"
# A build off uncommitted changes is not reproducible from the sha — mark it.
DIRTY=""
[ -n "$(git status --porcelain)" ] && DIRTY="-dirty"
# Date passed in (Date.now() is fine in bash); UTC so it sorts and matches server logs.
DATE="$(date -u +%Y%m%d-%H%M)"
LABEL="v${NAME}+${BUILD}-${SHA}${DIRTY}-${DATE}"
OUT="pguard-${LABEL}.apk"

echo "==> building pguard APK"
echo "    version : ${NAME}+${BUILD} (${SHA}${DIRTY})"
echo "    api host: ${API_HOST}"
echo "    artifact: ${OUT}"
[ -n "$DIRTY" ] && echo "    !! WORKING TREE IS DIRTY — this build is not reproducible from ${SHA}"

# ── build ────────────────────────────────────────────────────────────────────
( cd "$MOBILE" && flutter build apk --release \
    --dart-define=PGUARD_API_HOST="$API_HOST" \
    --build-name="$NAME" \
    --build-number="$BUILD" )

SRC="$MOBILE/build/app/outputs/flutter-apk/app-release.apk"
[ -f "$SRC" ] || { echo "!! build produced no APK at $SRC" >&2; exit 1; }

mkdir -p "$DIST"
cp "$SRC" "$DIST/$OUT"
SIZE="$(du -h "$DIST/$OUT" | cut -f1)"
echo "==> $DIST/$OUT ($SIZE)"

# ── log ──────────────────────────────────────────────────────────────────────
LOG="$DIST/BUILDS.tsv"
[ -f "$LOG" ] || printf 'utc_time\tversion\tsha\tdirty\tsize\tfile\n' > "$LOG"
printf '%s\t%s+%s\t%s\t%s\t%s\t%s\n' \
  "$DATE" "$NAME" "$BUILD" "$SHA" "${DIRTY:-clean}" "$SIZE" "$OUT" >> "$LOG"

# ── upload ───────────────────────────────────────────────────────────────────
if ! command -v rclone >/dev/null 2>&1; then
  echo "==> rclone not installed → skipping Drive upload (brew install rclone)"
  exit 0
fi
REMOTE_NAME="${DRIVE_REMOTE%%:*}"
if ! rclone listremotes 2>/dev/null | grep -qx "${REMOTE_NAME}:"; then
  echo "==> Drive remote '${REMOTE_NAME}' not configured → skipping upload."
  echo "    configure it once:  rclone config create ${REMOTE_NAME} drive   (then authorize in the browser)"
  exit 0
fi
DEST="${DRIVE_REMOTE}${DRIVE_DIR:+$DRIVE_DIR/}${OUT}"
echo "==> uploading to ${DEST}"
rclone copyto "$DIST/$OUT" "$DEST" --progress
echo "==> uploaded ${OUT} to Drive (${DEST})"
