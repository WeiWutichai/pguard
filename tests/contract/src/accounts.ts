// Deterministic seed accounts from v1-audit/perf-baseline/scripts/seed-v2.sql. Every seeded
// account shares one password. Logins go through the gateway (POST /v1/auth/login).
export const SEED_PASSWORD = "Password123!";

/** Argon2id PHC hash of SEED_PASSWORD, copied verbatim from seed-v2.sql — reused when an event
 *  test inserts a fresh pending guard so it can log in once approved. */
export const SEED_PASSWORD_HASH =
  "$argon2id$v=19$m=65536,t=3,p=4$LbU9CkFUHEsr1K1nM9vtMA$MmK8h5n8I8BduGu0WAYl0UDBDPox0EFoigjHeCOZijU";

export const ADMIN = {
  identifier: "0800000001",
  password: SEED_PASSWORD,
  userId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
} as const;

export const CUSTOMER = {
  identifier: "0820000001",
  password: SEED_PASSWORD,
  userId: "cccccccc-cccc-cccc-cccc-cccccccccccc",
} as const;

/** The dedicated test guard (seed-v2.sql line 51-59), approved + online. */
export const GUARD = {
  identifier: "0810000001",
  password: SEED_PASSWORD,
  userId: "99999999-9999-9999-9999-999999999999",
} as const;
