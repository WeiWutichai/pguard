---
name: v2 Security Additions
description: What v2 introduces beyond v1 baseline
type: project
---

# v2 security additions vs v1 baseline

## Closes (was missing in v1)

1. **token_revocation_version** — force-revoke-all on compromise
2. **Refresh family + rotation chain** — RFC 6749 §6 reuse detection
3. **Service-JWT** on `/internal/*` endpoints — `SERVICE_JWT_SECRET` separate from user JWT secret
4. **PIN backend validation** — no longer client-only; nginx + app-layer rate limit; per-device salt
5. **CSRF token middleware** on web state-changing endpoints
6. **WebSocket audit** — batch insert to `audit.gps_updates` + `audit.chat_events`
7. **Mutation audit** — `request_body_hash`, `response_status`, `old/new value hash` in `audit.logs`
8. **Read audit (opt-in)** — admin GETs of personal data logged for PDPA §30
9. **Rate limits** — nginx `s3_limit 10r/s`, `admin_limit 5r/s`, `pin_limit 3r/m`
10. **Per-user app-layer rate limit** — Redis token-bucket on `POST /payments` (10/day), `POST /attachments` (50/day)

## Strengthens (was weak in v1)

- Magic byte validation: still required, plus codec validation for video (HEVC reject ≥ Phase 2)
- Argon2 work factor: bumped to current OWASP recommendation
- JWT secret minimum: 64 chars (carried from v1's hardening)
- CORS: env-driven, never permissive (carried from v1)

## Deferred (v2.x)

- mTLS between services (requires cert rotation infra — Phase 5)
- DPoP / token binding (optional enterprise tier)
- Hardware-backed key storage (mobile)
