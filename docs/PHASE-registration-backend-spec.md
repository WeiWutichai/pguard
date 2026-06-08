# registration — backend account-creation + role + profile-submission (identity/profile) — work spec

> For Claude Code (Terminal C). The v2 backend has a **real gap**: `/otp/verify` issues a
> `phone_verified_token`, but **no endpoint consumes it to create an account**, and there's no
> role assignment. identity today = `login/refresh/logout/me/data-export/revoke-all` only;
> `services/identity/src/api/mod.rs` has no register/signup. The mobile `auth_controller.dart`
> even comments the token is *"reserved for the future registration endpoint."* This slice
> builds that endpoint + the profile-submission auth path, and writes the contracts. **This
> unblocks the mobile registration flow** (a later slice). Branch off freshly synced main.
> Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # must be at 38e91e6
git worktree add ../pguard-register -b feat/registration-backend main
cd ../pguard-register
```

## The v2 design (locked decisions — implement these; architecture-guardian confirms)
- **identity owns `users.role` and account state** — profile/otp must NOT write `auth/identity` schema (no cross-schema writes; CLAUDE.md Data rules).
- **Role is chosen at register time** (single step), not v1's 3-step progressive. CLAUDE.md (pguard) locks *"Strangler-fig: discipline only — no production users to protect"* → take the simpler clean path.
- **Register returns 202, no tokens.** A pending user cannot reach any protected endpoint until an admin approves (guard) / the customer profile is approved. Login works only after approval (confirm identity `login` already gates non-approved; if not, fix it).
- **Profile submission during registration uses a single-use `profile_token`** (purpose-scoped, issued by identity's register response, validated by profile via the shared `shared::auth` token scheme — same pattern as `phone_verified_token`). profile/guard|customer accept **either** a valid `profile_token` (initial registration, user not yet logged in) **or** `AuthUser` (later self-edit). Role is already set by identity at register, so profile only writes its **own** schema.

## Scope

### A. identity — `POST /auth/register`
Body `{ phone_verified_token, role: "guard"|"customer", pin_hash }` (pin_hash = client SHA-256 of PIN; identity Argon2's it as the password, via `spawn_blocking`).
- Decode + verify `phone_verified_token` (purpose `phone_verify`); **single-use** → Redis `GETDEL` on its jti. Reject reused/expired/forged.
- Extract phone from the token (don't trust a body phone). `validate_thai_phone()`.
- **UPSERT** user `ON CONFLICT (phone) DO UPDATE ... WHERE approval_status='pending'` (re-register a still-pending phone is fine; a non-pending phone → `Conflict("Please log in instead")`). Set `role` (guard/customer — reject `admin`), `approval_status='pending'`, Argon2(pin_hash).
- **Return 202** with `RegisterResult { user_id, profile_token }` — **no access/refresh tokens, no session row**. `profile_token` = single-use JWT (purpose `guard_profile`/`customer_profile` by role), jti stored `SET EX 900` in Redis.

### B. profile — accept `profile_token` on `POST /profile/{guard,customer}`
- Add a token auth mode: the handler accepts **either** `AuthUser` (Bearer) **or** a valid single-use `profile_token` whose purpose matches the route (`guard_profile`→/guard, `customer_profile`→/customer). Validate via `shared::auth` decode + Redis `GETDEL` on jti (single-use, purpose-isolated).
- On `profile_token` path the user is **not** logged in — derive `user_id` from the token's `sub`. Write **only** the profile schema (guard_profiles / customer_profiles). **Do NOT** touch `users.role` (identity already set it). customer profile → `approval_status='pending'`.
- Magic-byte + size validation already required for guard docs (JPEG/PNG/WEBP ≤10MB, size before magic bytes, parallel upload via JoinSet) — reuse the existing profile validators.

### C. shared::auth — profile-token scheme (if not already present)
- `ProfileTokenClaims` (sub=user_id, jti, purpose), `encode_profile_token(purpose) -> (token, jti)`, `decode_profile_token(expected_purpose) -> (user_id, jti)`. Purpose isolation: a guard token must fail on the customer route and vice-versa. Both identity + profile depend on `shared`, so the scheme + secret are shared (use the existing user `JWT_SECRET` or a dedicated `PROFILE_TOKEN_SECRET` — pick one, document it). Mirror the existing `phone_verified_token` helpers.

### D. Contracts (write/update to match)
- `contracts/openapi/identity.yaml` — add `/auth/register` (202, RegisterResult). Note the no-tokens-until-approved rule.
- `contracts/openapi/profile.yaml` — document the dual auth (Bearer **or** `profile_token`) on `/profile/guard` + `/profile/customer`.
- If a `PROFILE_TOKEN_SECRET` is introduced, add it to `infra/docker/docker-compose.prod.yml` via `${VAR:?}` + the env list.

## Out of scope (next slices)
- The Flutter registration screens (separate mobile slice — this contract unblocks it).
- Admin approval UI (web-admin) — the approve/reject endpoints already exist in profile.yaml.

## Definition of Done
- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅.
- **Unit/integration tests**: register creates a pending user + returns 202 **without** tokens; reused `phone_verified_token` rejected (GETDEL); non-pending phone → Conflict; admin role rejected; `profile_token` single-use + purpose-isolation (guard token fails on customer route); profile submission via `profile_token` writes profile but NOT `users.role`; login still blocked while pending, allowed after approval.
- No cross-schema write (architecture-guardian must confirm identity↔profile boundary held).
- Contracts updated + match handlers; `docker compose -f infra/docker/docker-compose.prod.yml config` still validates if you added a secret.
- Update `PROGRESS.md` (tick registration under Phase 4 + Completed-log row) · run the 3 review agents (security-reviewer especially — this is token/account-creation) · own PR off main · **don't merge**.

## Reference (read-only)
- Existing v2 token pattern to mirror: `shared::auth` `phone_verified_token` helpers; `services/otp` verify (issues the token). identity register UPSERT pattern + login approval gate: `services/identity/src/{api/mod.rs, repo/mod.rs}`.
- v1 logic (cite paths; adapt, don't copy): `../guard-dispatch/services/auth/` — `register_with_otp` (202 no tokens, UPSERT ON CONFLICT pending), `submit_guard_profile`/`submit_customer_profile` (profile_token single-use, atomic role set), `ProfileTokenClaims` purpose isolation. CLAUDE.md (guard-dispatch) "OTP Registration Flow" + the long Do-NOT list on register/profile_token are the rule set — **but** v2 sets role at register (identity-owned), so the role-assignment half is simpler than v1's progressive dance.
