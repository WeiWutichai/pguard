// Deterministic seed accounts (v1-audit/perf-baseline/scripts/seed-v2.sql) used by the web e2e.
// Everything the seed creates shares one password; logins go through the web-admin /v1 proxy.

/** The seeded super-admin (phone identifier + plaintext password). */
export const ADMIN = { identifier: "0800000001", password: "Password123!" } as const;

/** The plaintext password every seeded account uses. */
export const SEED_PASSWORD = "Password123!";

/** Argon2id PHC hash of SEED_PASSWORD, copied from seed-v2.sql. Reused when the approve→login spec
 *  inserts a fresh pending guard, so that guard authenticates with SEED_PASSWORD once approved. */
export const SEED_PASSWORD_HASH =
  "$argon2id$v=19$m=65536,t=3,p=4$LbU9CkFUHEsr1K1nM9vtMA$MmK8h5n8I8BduGu0WAYl0UDBDPox0EFoigjHeCOZijU";
