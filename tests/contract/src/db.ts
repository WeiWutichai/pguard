// Direct DB access for the event-contract tests: read emitted EventEnvelopes from the per-service
// transactional outbox, and seed the preconditions some events need (a pending guard to approve, a
// booking already in the arrived+work-started state a check-in requires).
//
// Mirrors tests/e2e/web/helpers/db.ts: by default we run psql INSIDE the compose `postgres`
// container (no host 5432 is published by the e2e stack). Override with PGUARD_E2E_PSQL for a
// direct psql invocation (space-tokenisable: binary + plain args only).
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";

import { SEED_PASSWORD, SEED_PASSWORD_HASH } from "./accounts.js";
import { REPO_ROOT } from "./specs.js";

const ENV_FILE = process.env.PGUARD_E2E_ENV_FILE ?? "infra/.env.e2e";
const PROD = "infra/docker/docker-compose.prod.yml";
const OVERRIDE = "infra/docker/docker-compose.e2e.yml";

/** Run SQL against the e2e Postgres, returning stdout (tuples-only, -tAc). Throws on SQL error.
 *  Values are test-controlled (uuids / fixed literals) — interpolation is intentional and safe. */
export function runSql(sql: string): string {
  const direct = process.env.PGUARD_E2E_PSQL;
  if (direct) {
    const [cmd, ...rest] = direct.split(" ").filter(Boolean);
    return execFileSync(cmd!, [...rest, "-v", "ON_ERROR_STOP=1", "-tAc", sql], {
      encoding: "utf8",
    }).trim();
  }
  return execFileSync(
    "docker",
    [
      "compose",
      "--env-file",
      ENV_FILE,
      "-f",
      PROD,
      "-f",
      OVERRIDE,
      "exec",
      "-T",
      "postgres",
      "psql",
      "-v",
      "ON_ERROR_STOP=1",
      "-U",
      process.env.POSTGRES_USER ?? "pguard",
      "-d",
      process.env.POSTGRES_DB ?? "pguard",
      "-tAc",
      sql,
    ],
    { cwd: REPO_ROOT, encoding: "utf8" },
  ).trim();
}

/**
 * Read the most recent EventEnvelope a service emitted to its outbox for a given topic, matched on
 * an inner-payload field (the outbox `payload` JSONB column holds the WHOLE envelope; business
 * fields live under payload->'payload'). Returns the parsed envelope, or null if no row matches.
 */
export function readOutboxEnvelope(
  table: string,
  topic: string,
  payloadField: string,
  payloadValue: string,
): unknown | null {
  const json = runSql(
    `SELECT payload FROM ${table} ` +
      `WHERE topic = '${topic}' ` +
      `AND payload->'payload'->>'${payloadField}' = '${payloadValue}' ` +
      `ORDER BY created_at DESC LIMIT 1;`,
  );
  if (!json) return null;
  return JSON.parse(json);
}

export interface PendingGuard {
  userId: string;
  phone: string;
  password: string;
}

/** Insert a fresh PENDING guard (identity.users + profile.guard_profiles), unique id+phone, reusing
 *  the seed password hash so it logs in once approved. (Same recipe as the web e2e.) */
export function createPendingGuard(): PendingGuard {
  const userId = randomUUID();
  const phone =
    "09" +
    (BigInt("0x" + userId.replace(/-/g, "").slice(0, 13)) % 100000000n).toString().padStart(8, "0");
  runSql(
    `INSERT INTO identity.users(id,phone,email,password_hash,role,approval_status,is_active) ` +
      `VALUES('${userId}','${phone}','${phone}@contract.local','${SEED_PASSWORD_HASH}','guard','pending',true);` +
      `INSERT INTO profile.guard_profiles(user_id,years_of_experience,gender,approval_status) ` +
      `VALUES('${userId}',2,'female','pending');`,
  );
  return { userId, phone, password: SEED_PASSWORD };
}

/**
 * Insert a booking already in the exact precondition a check-in requires: status='arrived' AND
 * work_started_at stamped (so hour_number=1 opens immediately). Assigned to `guardId`, owned by
 * `customerId`. Returns the new booking id. This is a test fixture for the progress_reported event;
 * the event itself is still emitted by the REAL booking service when the guard POSTs the check-in.
 */
export function insertArrivedBooking(customerId: string, guardId: string): string {
  const id = randomUUID();
  runSql(
    `INSERT INTO booking.bookings ` +
      `(id,customer_id,guard_id,status,address,scheduled_at,hours,base_fee,guard_count,tip,work_started_at) ` +
      `VALUES('${id}','${customerId}','${guardId}','arrived','1 Contract Test Rd',now(),4,500.00,1,0,now());`,
  );
  return id;
}
