---
name: Auth Flow Patterns
description: JWT, OTP, PIN, refresh, profile token — what v2 carries forward from v1
type: project
---

# Auth flow patterns (v2)

## JWT issuance (identity service)

- Access token: 15 min TTL, claims = `{sub, aud:"pguard", iss:"pguard-identity", iat, exp, jti, trv, role}`
- Refresh token: 7 day TTL, opaque random 32-byte (NOT a JWT — stored as hash in DB)
- Refresh row: `{id, user_id, hash, family_id, rotation_id, parent_rotation_id, expires_at, revoked_at}`
- Issue access: sign JWT with current `trv` from `auth.users.token_revocation_version`
- Issue refresh: insert row with new `family_id` (first issue) or same `family_id` + next `rotation_id` (rotation)

## Refresh rotation (CRITICAL — prevents reuse)

```sql
-- Single atomic transaction
BEGIN;
UPDATE auth.refresh_tokens
   SET revoked_at = NOW()
 WHERE family_id = $1 AND rotation_id = $2 AND revoked_at IS NULL
RETURNING parent_rotation_id;

-- If 0 rows affected → this refresh was already rotated → token reuse
-- → revoke entire family + raise compromised user event

UPDATE auth.refresh_tokens
   SET revoked_at = NOW()
 WHERE family_id = $1 AND revoked_at IS NULL;

-- Emit pguard.events.user.compromised → identity bumps token_revocation_version

INSERT INTO auth.refresh_tokens (id, user_id, hash, family_id, rotation_id, parent_rotation_id, expires_at)
VALUES (..., $1, current_rotation + 1, current_rotation, NOW() + 7 days);
COMMIT;
```

## Force-revoke-all-tokens

When user account compromise detected:
1. `UPDATE auth.users SET token_revocation_version = token_revocation_version + 1 WHERE id = $1`
2. Emit `pguard.events.user.compromised`
3. All future JWT decodes compare `jwt.trv` vs `Redis cached user_trv:{user_id}` — if `<` → reject
4. Cache TTL = 60s (acceptable lag); invalidated on revoke via PubSub

## OTP

- 6-digit code, 5-min TTL
- Constant-time compare (`subtle::ConstantTimeEq`)
- Atomic `SET NX EX` for per-phone cooldown (90s between requests)
- Daily cap: per-phone INCR with TTL recovery (TTL < 0 → set EXPIRE)
- Attempts counter: `UPDATE WHERE id = (SELECT FOR UPDATE)` — never separate SELECT then UPDATE
- After 5 wrong attempts on same code → invalidate, force new request

## phone_verified_token

- JWT, 24-hour TTL, claims `{sub:phone, aud:"pguard-phone-verify", jti}`
- jti stored in Redis `phone_verified_jti:{jti}` with TTL matching exp
- Validated via `GET` (not GETDEL) — re-usable for role re-selection within window
- Consumed (GETDEL) only when profile_token is issued by `/profile/role`

## profile_token (purpose-isolated)

- JWT, 15-min TTL, claims `{sub:user_id, purpose:"guard_profile"|"customer_profile", jti}`
- jti stored in Redis `profile_jti:{jti}` = "valid"
- Single-use via GETDEL when submit_guard_profile or submit_customer_profile succeeds
- Purpose mismatch → reject (guard token cannot be used to submit customer profile)

## PIN (v2 changes from v1)

- Validation moves to backend (`POST /auth/pin/verify` → returns short-lived JWT)
- nginx `pin_limit 3r/m` per IP on this endpoint
- App-layer rate limit: 5 attempts per device per 60s (track via `device_id` header)
- Per-device salt: stored locally in FlutterSecureStorage, used in hash; salt NOT transmitted
- Argon2 (not SHA-256) even for client-side hash sent to server
- After 10 failed → backend invalidates all sessions + clears PIN hash + emits force-re-OTP signal

## Login isolation

- Web: `POST /v1/auth/login/web` → httpOnly+Secure cookies (no tokens in body)
- Mobile: `POST /v1/auth/login/mobile` → tokens in JSON body
- Never trust `X-Client-Type` header to switch behavior — separate endpoints only
