# syntax=docker/dockerfile:1
# ─────────────────────────────────────────────────────────────────────────────
# pguard v2 — PRIMARY Postgres image (C5.3 streaming replication).
#
# WHY a custom image instead of a bind-mounted init script:
#   docker-entrypoint.sh runs /docker-entrypoint-initdb.d/*.sh ONCE on first init. On
#   Docker Desktop (macOS, gRPC-FUSE / virtiofs) a bind-mounted host file can lose its
#   exec bit or not be present at the instant initdb scans the dir → the replication
#   bootstrap (10-replication.sh) silently never runs → no `replicator` role / slot /
#   pg_hba line → the replica's pg_basebackup fails forever and the whole stack hangs.
#
#   Baking the script INTO the image (COPY + chmod +x) makes it part of the read-only
#   image layer — it is always present and executable at initdb, race-free, no host mount.
#
#   Build context = repo root (so the COPY can reach infra/db/), matching the other images:
#     docker build -f infra/docker/postgres-primary.Dockerfile -t pguard/postgres-primary:17 .
# ─────────────────────────────────────────────────────────────────────────────
FROM postgres:17

# Streaming-replication bootstrap — creates the dedicated `replicator` role, a physical
# replication slot, and the scoped pg_hba line. Runs at first initdb only.
COPY infra/db/primary-replication-init.sh /docker-entrypoint-initdb.d/10-replication.sh
RUN chmod 0755 /docker-entrypoint-initdb.d/10-replication.sh
