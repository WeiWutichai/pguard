// Direct DB access for e2e fixtures. The approve→login flow needs a *pending* guard to approve, and
// seed-v2 only creates approved ones — so the spec inserts its own. A fresh unique guard per run
// keeps the test re-runnable without a reset step.
//
// Local default: run psql INSIDE the compose `postgres` container (the same path migrate.sh uses).
// CI / non-docker: set PGUARD_E2E_PSQL to a direct psql invocation against the DB, e.g.
//   PGUARD_E2E_PSQL="psql postgresql://pguard:pguard_dev_pw@localhost:5432/pguard"
// (must be space-tokenisable — the binary + plain args only, no quoted args with embedded spaces.)
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import path from "node:path";

import { SEED_PASSWORD, SEED_PASSWORD_HASH } from "./accounts";

// tests/e2e/web/helpers → repo root (four levels up).
const REPO_ROOT = path.resolve(__dirname, "..", "..", "..", "..");
const ENV_FILE = process.env.PGUARD_E2E_ENV_FILE ?? "infra/.env.e2e";
const PROD = "infra/docker/docker-compose.prod.yml";
const OVERRIDE = "infra/docker/docker-compose.e2e.yml";

/** Execute SQL against the e2e Postgres and return stdout (tuples-only). Throws on a SQL error
 *  (ON_ERROR_STOP). Values are controlled by the test (no external input) — interpolation is safe. */
export function runSql(sql: string): string {
  const direct = process.env.PGUARD_E2E_PSQL;
  if (direct) {
    const [cmd, ...rest] = direct.split(" ").filter(Boolean);
    return execFileSync(cmd, [...rest, "-v", "ON_ERROR_STOP=1", "-tAc", sql], {
      encoding: "utf8",
    });
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
  );
}

export interface PendingGuard {
  userId: string;
  phone: string;
  password: string;
}

/** Insert a fresh PENDING guard (identity.users + profile.guard_profiles) with a unique id+phone.
 *  Reuses the seed password hash so it logs in with SEED_PASSWORD *after* it's approved. */
export function createPendingGuard(): PendingGuard {
  const userId = randomUUID();
  // Thai mobile: "09" + 8 digits DERIVED from the (unique) uuid, so the phone is as collision-free
  // as the id itself — no separate Math.random() that could clash with identity.users(phone) UNIQUE.
  const phone =
    "09" + (BigInt("0x" + userId.replace(/-/g, "").slice(0, 13)) % 100000000n).toString().padStart(8, "0");
  runSql(
    `INSERT INTO identity.users(id,phone,email,password_hash,role,approval_status,is_active) ` +
      `VALUES('${userId}','${phone}','${phone}@e2e.local','${SEED_PASSWORD_HASH}','guard','pending',true);` +
      `INSERT INTO profile.guard_profiles(user_id,years_of_experience,gender,approval_status) ` +
      `VALUES('${userId}',2,'female','pending');`,
  );
  return { userId, phone, password: SEED_PASSWORD };
}
