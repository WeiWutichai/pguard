#!/bin/bash
# pguard primary Postgres — streaming-replication bootstrap (C5.3 read replica).
#
# Runs ONCE on first init (mounted into /docker-entrypoint-initdb.d/). Creates a dedicated
# least-privilege replication role + a physical replication slot, and allows the replica to
# open streaming connections. The replica (postgres-replica) then `pg_basebackup`s from here
# and streams WAL. REPLICATION_PASSWORD is required (compose passes it via ${VAR:?}).
set -euo pipefail

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
  CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';
  SELECT pg_create_physical_replication_slot('replica_1');
EOSQL

# Allow streaming replication from the compose network (scram-sha-256 auth, not trust).
echo "host replication replicator all scram-sha-256" >> "$PGDATA/pg_hba.conf"
pg_ctl reload -D "$PGDATA"
