#!/usr/bin/env bash
# ── ONE-TIME OSRM data prep for the self-hosted `osrm` service (Thailand) ─────────────────────────
# Run this ON THE VPS once BEFORE the first `docker compose ... up -d osrm`. It downloads the
# Thailand OSM extract and preprocesses it (extract → partition → customize, the MLD pipeline that
# `osrm-routed --algorithm mld` serves) into $OSRM_DATA_DIR, which the `osrm` service mounts read-only.
# Needs ~4 GB RAM + ~2 GB disk; the extract step takes a few minutes. Re-run to refresh the map.
#
#   bash infra/docker/osrm-prep.sh
#   docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/.env up -d osrm
#
set -euo pipefail

DATA_DIR="${OSRM_DATA_DIR:-/opt/pguard-osrm}"
PBF_URL="${OSRM_PBF_URL:-https://download.geofabrik.de/asia/thailand-latest.osm.pbf}"
IMG="${OSRM_IMAGE:-ghcr.io/project-osrm/osrm-backend:latest}"
PROFILE="/opt/car.lua"   # car routing; motorcycle ≈ car, walk ETA is derived client-side

mkdir -p "$DATA_DIR"
echo "==> downloading $PBF_URL"
curl -fL --retry 3 -o "$DATA_DIR/thailand-latest.osm.pbf" "$PBF_URL"

echo "==> osrm-extract (heavy; a few minutes)"
docker run --rm -v "$DATA_DIR:/data" "$IMG" osrm-extract -p "$PROFILE" /data/thailand-latest.osm.pbf
echo "==> osrm-partition"
docker run --rm -v "$DATA_DIR:/data" "$IMG" osrm-partition /data/thailand-latest.osrm
echo "==> osrm-customize"
docker run --rm -v "$DATA_DIR:/data" "$IMG" osrm-customize /data/thailand-latest.osrm

echo "==> done. Files in $DATA_DIR:"
ls -lh "$DATA_DIR"/thailand-latest.osrm* 2>/dev/null | head
echo "Now start it:  docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/.env up -d osrm"
echo "The api-gateway already points OSRM_PRIMARY_URL at http://osrm:5000 (internal)."
