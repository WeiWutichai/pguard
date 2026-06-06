#!/bin/bash
# pguard primary Postgres — streaming-replication bootstrap (C5.3 read replica).
#
# Runs ONCE on first init (mounted into /docker-entrypoint-initdb.d/). Creates a dedicated
# least-privilege replication role + a physical replication slot, and allows the replica to
# open streaming connections. The replica (postgres-replica) then `pg_basebackup`s from here
# and streams WAL. REPLICATION_PASSWORD is required (compose passes it via ${VAR:?}).
set -euo pipefail

# Pass the password as a psql variable (`:'repl_pw'` quotes + escapes it safely) instead of
# shell-interpolating it into the SQL text — so a password containing a single quote can't
# break or alter the CREATE ROLE statement. Heredoc is quoted (no shell expansion).
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
     -v repl_pw="$REPLICATION_PASSWORD" <<-'EOSQL'
  CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD :'repl_pw';
  SELECT pg_create_physical_replication_slot('replica_1');
EOSQL

# Allow streaming replication ONLY from this compose network's CIDR (matches the
# pguard-prod ipam subnet) — scram-sha-256 auth, never trust, never any-source `all`.
echo "host replication replicator 172.30.0.0/16 scram-sha-256" >> "$PGDATA/pg_hba.conf"
pg_ctl reload -D "$PGDATA"
