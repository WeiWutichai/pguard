# Phase 5 — C5.4 security sweep (the last Phase 5 backend slice) — work spec

> For Claude Code. Close the remaining `v1-audit/03-security.md` risks, confirm the
> hardening already in place, and fix the one known footgun. Mostly verification +
> small targeted fixes. **Use `contracts/openapi/*.yaml` + the actual route tables as the
> source of truth — do NOT assume endpoint paths.** Branch off the freshly synced main,
> one backend track. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 3940251
git worktree add ../pguard-c54 -b feat/c5.4-security-sweep main
```

## Scope

### A. Targeted fix — otp `SMS_DISABLED` footgun (real bug)
`services/otp/src/main.rs` gates SMS with `std::env::var("SMS_DISABLED").is_ok()` —
**presence-based**, so any value (incl. `"false"`) disables real SMS. Make it
**value-aware** (disable only for truthy values like `true`/`1`/`yes`, case-insensitive;
treat `false`/`0`/unset as enabled). Add a unit test covering `true`/`false`/unset.

### B. Authz / coverage audit (fix what's missing)
- Every `/internal/*` endpoint is **service-JWT gated** (ServiceCaller) — grep for internal routes, confirm each requires it; fix any that don't.
- No `_user: AuthUser` (ignored user) on endpoints that need ownership/role checks — grep + fix.
- The gateway enforces JWT-at-edge (jti blocklist + per-user trv + CSRF) on all authed `/v1/*`; backends keep their own `AuthUser` (defense-in-depth). Confirm no authed route is reachable unauthenticated.

### C. Edge hardening (gateway)
- Per-IP rate-limit tiers present + sensible (auth/otp tighter); confirm parity with the v1 nginx zones.
- Security headers on responses (X-Frame-Options, X-Content-Type-Options, Referrer-Policy, etc.).
- Swagger/docs gated by `ENABLE_SWAGGER` (absent → 404 in prod). No `CorsLayer::permissive()`; CORS from `CORS_ALLOWED_ORIGINS`.

### D. Secrets / Docker (verify #9's work)
- All secrets via `${VAR:?}` (no defaults, no `minioadmin`); runtime images non-root + stripped; only the gateway publishes host ports. Confirm + fix any gap.

### E. Deliverable — security checklist
- Write `v1-audit/03-security-v2-checklist.md` (mirrors `03-security.md`'s top risks): each item ✅/⚠️ with the file + line proving it. This is the artifact that says "v2 closed the v1 security risks."

## Definition of Done
- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅ (incl. the new otp value-aware test + any added authz test).
- otp `SMS_DISABLED` is value-aware with a test.
- Coverage audit done; any missing service-JWT / authz gap fixed with a test.
- `03-security-v2-checklist.md` complete with per-item proof.
- Update `PROGRESS.md` (tick + Completed-log row → **Phase 5 complete**) · run the 3 review agents (this is their home turf) · own PR off main · don't merge.

## Reference (read-only)
- `v1-audit/03-security.md` (top 15 risks — the checklist target) · `v1-audit/07-pdpa.md` · CLAUDE.md "Security" Do/Don't (JWT, audit middleware, OTP, CORS, Docker). The patterns already exist in `services/api-gateway` (edge) + `packages/shared-rust` (service_jwt, auth) — reuse, don't reinvent.
