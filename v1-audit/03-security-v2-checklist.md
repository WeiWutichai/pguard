# 03 · Security Posture — **v2 closure checklist**

> Companion to [`03-security.md`](03-security.md). Each v1 risk/control is re-stated with
> its **v2 status** and the **file + line that proves it** (paths relative to the `pguard`
> repo root). Produced by the C5.4 security sweep (`feat/c5.4-security-sweep`).
>
> Legend: ✅ closed · ⚠️ partial / deferred (with reason) · 🆕 added or hardened by this sweep.
>
> Verification basis: `contracts/openapi/*.yaml` + the **actual** Axum route tables + the
> v1 nginx.conf (`../guard-dispatch/nginx/nginx.conf`, read-only). DoD: `cargo clippy
> --workspace --all-targets -- -D warnings` clean · `cargo test --workspace` 376 passed / 0
> failed / 1 ignored.

---

## 3.6 Top 15 Security Risks — v2 status

| # | v1 risk | Sev | v2 status | Proof (file:line) |
|---|---|---|---|---|
| 1 | No force-revoke-all-tokens (account compromise) | 🔴 | ✅ **Closed** — per-user `token_revocation_version` (trv) checked on every decode at the edge **and** in each backend; `delete_me` / `internal_revoke_all` bump it; `pguard.events.user.compromised` topic exists. | `packages/shared-rust/src/auth.rs:143` (trv check in `AuthUser`); `services/api-gateway/src/auth.rs:99-106` (edge trv); `services/identity/src/api/mod.rs:259` (`delete_me`), `:324` (`internal_revoke_all`) |
| 2 | PIN brute-force (no rate limit on mobile PIN) | 🔴 | ⚠️ **Partial** — edge auth tier (5 r/s) + otp tier (10 r/m) per-IP are in place; PIN-hash salt + a dedicated `/login/mobile`-style 3 r/m limit are **mobile/identity** concerns tracked in Phase 4 (Flutter). The backend exposes no unauthenticated PIN endpoint in this slice. | `services/api-gateway/src/domain/ratelimit.rs:24-28`; `services/api-gateway/src/main.rs:141-147` |
| 3 | Refresh reuse detection missing | 🔴 | ✅ **Closed** — RFC 6749 §6 rotation chain (`family_id` + `rotation_id`); replay of a rotated token → `ReuseDetected` → revoke entire family. | `services/identity/src/api/mod.rs:118-149` (`refresh`, `ReuseDetected` → `revoke_family`); `services/identity/src/domain/rotation.rs` (`decide`); `services/identity/src/repo/mod.rs` (`create_refresh_family` / `find_refresh_by_rotation` / `revoke_family` / `rotate`) |
| 4 | `/minio-files/` no rate limit (exfil DoS) | 🟠 | ✅ **Vector removed** — v2 has **no app-proxied file endpoint**; binary blobs live in S3/R2 (keys + metadata only in PG, per CLAUDE.md). When upload endpoints land (profile docs / chat attachments, later slices) they must get an upload-specific tier. | No `minio`/`presign`/`/files`/`upload` route in any `services/*/src/main.rs` or `services/api-gateway/src/domain/routing.rs` |
| 5 | Admin endpoints share public rate limit | 🟠 | ⚠️ **Partial** — admin endpoints are **role-gated** (require an admin JWT) so the *public* DoS vector is closed; a dedicated tighter admin tier (v1's recommended `admin_limit 5 r/s`) is **not** implemented — admin routes use the `api` tier (30 r/s). | role gate: `services/profile/src/api/mod.rs:37-44` (`require_role(ROLE_ADMIN)`), `services/payment/src/api/mod.rs:112-116`, `services/rating/src/api/mod.rs:122-126`; tiers: `services/api-gateway/src/domain/ratelimit.rs:24-28` |
| 6 | WebSocket (GPS/chat) not audited | 🟠 | ⚠️ **Deferred** — presence/chat real-time handlers are not built in this backend slice (presence/chat are skeletons); WS audit (`audit.gps_updates`/`audit.chat_events`) lands with those handlers. | `services/presence/` + `services/chat/` (no WS message handler yet) |
| 7 | Audit log lacks status code | 🟠 | ⚠️ **Deferred** — no cross-service audit middleware yet. | (no `audit.logs` middleware in `packages/`/`services/`) |
| 8 | Audit log lacks body / old-new value | 🟠 | ⚠️ **Deferred** — see #7. | — |
| 9 | **Internal endpoint without auth (`/internal/push`)** | 🟠 | ✅ **Closed** — every `/internal/*` route is `ServiceCaller`-gated (service-JWT, separate `SERVICE_JWT_SECRET`, `iss=pguard`/`aud=pguard-internal`/`exp`), and the gateway **blocks** `/internal/*` at the edge (404, encoded-separator safe). | `packages/shared-rust/src/service_jwt.rs:83-102` (extractor rejects missing/invalid); `services/notification/src/api/mod.rs:141` (the v1-vulnerable push, now gated); gateway block: `services/api-gateway/src/domain/routing.rs:148-161` + `handler.rs:67-68`. Full inventory below. |
| 10 | No CSRF token (web) | 🟡 | ✅ **Closed** — cookie-based state-changing calls require `X-Requested-With`, enforced at the **edge** and in **each backend**. | `services/api-gateway/src/auth.rs:75-82`; `packages/shared-rust/src/auth.rs:192-201` |
| 11 | Audit doesn't cover reads | 🟡 | ⚠️ **Partial** — admin reads of guard profiles are audited (`profile.access_audit`: accessed_by/action/target); broader read-audit pending the audit middleware. | `services/profile/src/repo/mod.rs:344` |
| 12 | PIN hash no salt | 🟡 | ⚠️ **Mobile** — per-device PIN salt is a Flutter concern (Phase 4); not in backend scope. | (mobile `apps/mobile`) |
| 13 | WS message rate limit (in-app) | 🟡 | ⚠️ **Deferred** — see #6 (presence/chat WS handlers not yet built). | — |
| 14 | No secret rotation | 🟡 | ⚠️ **Process** — secrets are externalized via `${VAR:?}` (no defaults), enabling rotation; a quarterly rotation runbook is an ops doc, not code. | `infra/docker/docker-compose.prod.yml` (`JWT_SECRET`/`SERVICE_JWT_SECRET` via `${VAR:?}`) |
| 15 | Presigned URL cache stale (403) | 🟡 | ⚠️ **Mobile** — client cache refresh is a Flutter concern; no backend surface. | (mobile `apps/mobile`) |

**Backend security risks closed by v2 design + this sweep: #1, #3, #4, #9, #10 (5/5 in scope).**
Remaining items are mobile (#2 partial, #12, #15), ops process (#14), or cross-cutting audit/WS
work deferred to their owning slices (#5 partial, #6, #7, #8, #11 partial, #13).

---

## `/internal/*` route inventory — all service-JWT gated (risk #9)

Every internal route takes the `ServiceCaller` extractor (`packages/shared-rust/src/service_jwt.rs:83-102`,
which 401s on missing/invalid/expired service-JWT) and is **blocked at the public edge** (404):

| Method · path | Service | Handler proof |
|---|---|---|
| `POST /internal/users/{id}/revoke-all` | identity | `services/identity/src/main.rs:109` · `api/mod.rs:326` |
| `GET /internal/guards` | profile | `services/profile/src/main.rs:84` · `api/mod.rs:211` |
| `GET /internal/users/{id}/export` | profile | `services/profile/src/main.rs:88` · `api/mod.rs:233` |
| `GET /internal/bookings/{id}` | booking | `services/booking/src/main.rs:141` · `api/mod.rs:351` |
| `GET /internal/users/{id}/export` | booking | `services/booking/src/main.rs:145` · `api/mod.rs:365` |
| `GET /internal/users/{id}/export` | payment | `services/payment/src/main.rs:120` · `api/mod.rs:174` |
| `GET /internal/guards/{id}/rating-summary` | rating | `services/rating/src/main.rs:106` · `api/mod.rs:175` |
| `GET /internal/users/{id}/export` | rating | `services/rating/src/main.rs:110` · `api/mod.rs:193` |
| `POST /internal/notifications/push` | notification | `services/notification/src/main.rs:99` · `api/mod.rs:141` |

Edge block (defense-in-depth): `services/api-gateway/src/domain/routing.rs:148-161`
(`is_internal` on raw **and** post-`/v1`-strip path; `has_encoded_separator` blocks `%2f`/`%5c`)
→ `handler.rs:67-68` returns **404** (not 403, so existence isn't disclosed).

---

## Authorization coverage — no ignored user, no unauthenticated authed route

- **No ignored `AuthUser`**: grep for `_user: AuthUser` / `_: AuthUser` / `_claims` across
  `services/**/*.rs` → **0 matches**. Every handler that extracts `AuthUser` uses the identity.
- **Ownership / role gates** (sample, all verified): booking `get_booking`/`list_bookings`
  scope to caller or assigned guard (`services/booking/src/api/mod.rs:262-286`); payment
  `get_payment` checks `customer_id == caller || role==admin` (`services/payment/src/api/mod.rs:142-154`);
  rating `submit_review` derives the guard from the authoritative booking, never from the
  request (`services/rating/src/api/mod.rs:39-95`); calling `initiate_call` derives the callee
  from the booking (`services/calling/src/api/mod.rs:32-70`); profile mutations are role-gated
  (`services/profile/src/api/mod.rs:90-114`).
- **Default-protected edge**: the gateway's public allowlist is a **tight, exact** set —
  `PUBLIC_PATHS = {/auth/login, /auth/refresh, /otp/challenge, /otp/request, /otp/verify}`
  (`services/api-gateway/src/domain/routing.rs:136-142`); everything else under a known prefix
  is token-validated at the edge **before** proxying (`handler.rs:95-104`), with a completeness
  test (`routing.rs` `exact_public_allowlist`). Backends keep their own `AuthUser`
  (`packages/shared-rust/src/auth.rs:156-213`) as defense-in-depth.
- **Intentionally public reads** (require an edge token but no ownership check): `guard_ratings`
  (`services/rating/src/api/mod.rs:100`, public visible-ratings view) — by design, not a gap.

---

## 3.2 JWT / Session — v2 status

| v1 gap | v2 status | Proof |
|---|---|---|
| Force-revoke-all missing | ✅ trv per-user (risk #1) | `packages/shared-rust/src/auth.rs:143`; `services/api-gateway/src/auth.rs:99-106` |
| Refresh reuse detection missing | ✅ RFC 6749 §6 family/rotation (risk #3) | `services/identity/src/api/mod.rs:118-149` |
| Internal endpoint no auth | ✅ service-JWT (risk #9) | `packages/shared-rust/src/service_jwt.rs` |
| mTLS between services | ⚠️ deferred v2.x (needs cert-rotation infra) — service-JWT + network isolation in the interim | — |
| Token binding / DPoP | ⚠️ deferred (optional enterprise tier) | — |
| jti revocation blocklist | ✅ carried forward — `revoked_jti:{jti}` checked at edge + backend | `services/api-gateway/src/auth.rs:90-96`; `packages/shared-rust/src/auth.rs` |

---

## 3.3 Rate Limiting — v2 parity with **deployed** v1 nginx zones

Per-IP, Redis fixed-window, fail-OPEN, env-overridable (`services/api-gateway/src/domain/ratelimit.rs:24-28`,
`main.rs:141-147`):

| Zone | v1 nginx (actual) | v2 gateway tier | Status |
|---|---|---|---|
| auth | `rate=5r/s` (`nginx.conf:44`) | `auth_per_sec: 5` | ✅ parity |
| otp | `rate=10r/m` (`nginx.conf:50`) | `otp_per_min: 10` | ✅ parity |
| api | `rate=30r/s` (`nginx.conf:45`) | `api_per_sec: 30` | ✅ parity |
| ws | `rate=5r/s` (`nginx.conf:46`) | edge auth on `/v1/ws/bookings/{id}`; presence/chat WS tiers land with those handlers | ⚠️ partial |
| swagger | `rate=10r/s` | **N/A** — no Swagger UI served in v2 (see 3.5) | ✅ n/a |

> Note: `03-security.md §3.3` lists otp as "3r/m" — that is the **recommended** tighter limit
> for the mobile login endpoint (risk #2 fix), **not** the deployed `otp_limit` zone, which is
> `10r/m` in the actual `nginx.conf:50`. v2 matches the deployed zone exactly.

Architectural improvement over v1: rate limiting is no longer nginx-only. It runs at the
gateway **and** every internal route requires a service-JWT, so "bypass nginx → hit the
service directly" (v1 §3.3 architectural concern) no longer grants unauthenticated access.

---

## 3.5 Other — v2 status

| Area | v2 status | Proof |
|---|---|---|
| 🆕 **Security response headers** | ✅ **Added by this sweep** — X-Frame-Options `DENY`, X-Content-Type-Options `nosniff`, Referrer-Policy `strict-origin-when-cross-origin`, X-XSS-Protection `0` (OWASP-current), HSTS `max-age=31536000; includeSubDomains`, CSP `default-src 'none'; frame-ancestors 'none'`, Permissions-Policy `camera=(), microphone=(), geolocation=()`. Stamped on **every** response (proxied / error / CORS) as the outermost layer. v1 set 5 of these at nginx; v2 adds HSTS + CSP. | `services/api-gateway/src/domain/headers.rs` (`security_headers`); `services/api-gateway/src/handler.rs` (`security_headers_mw`); `services/api-gateway/src/main.rs` (outermost `.layer(...)`) |
| CORS (not permissive) | ✅ env-driven allowlist (`CORS_ALLOWED_ORIGINS`), `allow_credentials(true)` (forbids `*`); **no** `CorsLayer::permissive()` anywhere. | `packages/shared-rust/src/config.rs:29-54` (`build_cors_layer`); `services/api-gateway/src/main.rs:121` |
| Swagger/docs gating | ✅ **No Swagger UI surface** — `utoipa` is used only for `#[derive(ToSchema)]` (OpenAPI component codegen); `utoipa-swagger-ui` is declared in workspace deps but **mounted by no service** (absent from the build graph). Any `/swagger`/`/docs` path → 404 (no route). | `packages/shared-rust/src/{models,error,auth}.rs` (ToSchema only); no `SwaggerUi`/`swagger_ui` in any `services/**/*.rs` |
| Web cookie auth (httpOnly+Secure+SameSite) + CSRF | ✅ CSRF closed (risk #10) | `services/api-gateway/src/auth.rs:75-82` |
| Spoofable identity headers | ✅ inbound `x-user-*` stripped; gateway injects from the verified JWT | `services/api-gateway/src/domain/headers.rs` (`is_spoofable_identity`); `proxy.rs` |
| Request body bomb | ✅ 1 MiB cap → 413 | `services/api-gateway/src/proxy.rs` (`MAX_BODY_BYTES`) |
| Trace-context forgery | ✅ edge starts a fresh root trace; client `traceparent`/`tracestate` stripped | `services/api-gateway/src/main.rs:112-124` (edge telemetry); `proxy.rs` |
| Metrics exposure | ✅ `/metrics` on a **separate** admin port, never on the public edge | `services/api-gateway/src/main.rs:38-41,89-110` |

---

## 🆕 otp `SMS_DISABLED` footgun — fixed by this sweep

v1/early-v2 gated the real SMS sender with **presence-based** `std::env::var("SMS_DISABLED").is_ok()`
— any value (even `"false"`) silently disabled real SMS. Now **value-aware**: disabled only for
truthy values (`true`/`1`/`yes`/`on`/`y`, case-insensitive, trimmed); `false`/`0`/empty/unset keep
real SMS **on**.

- helper: `packages/shared-rust/src/config.rs` (`parse_env_bool`) + tests
- otp policy seam: `services/otp/src/sms.rs` (`sms_disabled`) + tests (truthy / `false`/`0`/empty / unset)
- call site: `services/otp/src/main.rs:60`

---

## Secrets / Docker hardening (CLAUDE.md "Docker") — verified

| Control | Status | Proof |
|---|---|---|
| Secrets via `${VAR:?}` (no defaults, no `minioadmin`) | ✅ JWT/SERVICE_JWT/POSTGRES/REPLICATION/MINIO_ROOT/GRAFANA/INET creds all fail-fast | `infra/docker/docker-compose.prod.yml` (`${JWT_SECRET:?}`, `${SERVICE_JWT_SECRET:?}`, `${POSTGRES_PASSWORD:?}`, `${MINIO_ROOT_PASSWORD:?}`, …) |
| Non-credential defaults only where safe | ✅ `POSTGRES_USER:-pguard`, `RUST_LOG:-info`, rate-limit/OTP knobs | `docker-compose.prod.yml` |
| Runtime non-root | ✅ Rust services `appuser` (uid 10001), web-admin `node` (uid 1000), replica `user: postgres` | `infra/docker/rust-service.Dockerfile:62-63,73`; `web-admin.Dockerfile:44-57` |
| Stripped release binaries | ✅ Dockerfile `strip` **and** 🆕 `[profile.release] strip = true` (CI/local parity) | `infra/docker/rust-service.Dockerfile:54`; `Cargo.toml` `[profile.release]` |
| Only the gateway publishes host ports | ✅ gateway `3000` only; all other services `expose:` (MediaSoup UDP 40000-49999 is the documented WebRTC exception) | `docker-compose.prod.yml` (gateway `ports:`, others `expose:`) |
| `no-new-privileges`, pinned images, healthchecks | ✅ `security_opt: [no-new-privileges:true]` on all Rust services; no `:latest` in prod; HEALTHCHECK everywhere | `docker-compose.prod.yml` (x-rust-service anchor); `rust-service.Dockerfile:77-78` |
| Dev image runs as root | ⚠️ `infra/docker/Dockerfile.dev` has no `USER` — **dev-only**, acceptable (prod images are non-root). | `infra/docker/Dockerfile.dev` |

---

## PDPA (`07-pdpa.md`) — v2 status (highlights)

| PDPA item | v2 status | Proof |
|---|---|---|
| Right to erasure (§33) | ✅ `DELETE /auth/me` soft-deletes + bumps trv (force-logout) | `services/identity/src/api/mod.rs:259` (`delete_me`) |
| Data export / access (§19) | ✅ `GET /me/data-export` fans out to each owner's service-JWT'd `/internal/users/{id}/export` | `services/identity/src/api/mod.rs:289` (`data_export`); per-service `/internal/users/{id}/export` (profile/booking/payment/rating) |
| Read-access audit (admin personal data, §6) | ⚠️ partial — profile admin reads audited (`profile.access_audit`); broader coverage pending audit middleware | `services/profile/src/repo/mod.rs:344` |
| Privacy notice / consent (§30/§31), retention/purge (§37), breach runbook (§34), cross-border (R2/FCM) | ⚠️ deferred — product/ops + later slices | `07-pdpa.md:87-95` |

---

## Definition-of-Done evidence

- `cargo clippy --workspace --all-targets -- -D warnings` → clean.
- `cargo test --workspace` → **376 passed, 0 failed, 1 ignored** (incl. `parse_env_bool_*`,
  `sms_disabled_*`, `security_headers_*`, `security_headers_mw_stamps_ok_and_error_responses`).
- Fixes this sweep: otp value-aware `SMS_DISABLED` (A), security response headers at the edge
  (C), `[profile.release] strip = true` (D). Authz/internal-route coverage (B) audited — **no
  gaps**. Checklist (E) = this file.
