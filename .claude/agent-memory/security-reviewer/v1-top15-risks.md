---
name: v1 Top 15 Security Risks
description: Ranked from ../guard-dispatch/v2-audit/03-security.md §3.6 — gate for v2 launch
type: project
---

| # | Risk | Severity | v2 fix |
|---|---|---|---|
| 1 | No force-revoke-all-tokens (account compromise) | 🔴 CRITICAL | `token_revocation_version` per user, increment + 1 Redis GET per decode |
| 2 | PIN brute-force (~55hr single IP / ~1hr distributed) | 🔴 CRITICAL | move PIN validate to backend, nginx 3r/m, app-layer 5/60s/device, per-device salt, Argon2 |
| 3 | Refresh reuse not detected | 🔴 CRITICAL | RFC 6749 §6 rotation chain: family_id + rotation_id; reuse → revoke family + alert |
| 4 | /minio-files/ no rate limit (exfil DoS) | 🟠 HIGH | nginx `s3_limit 10r/s` |
| 5 | admin endpoint same rate as public | 🟠 HIGH | nginx `admin_limit 5r/s` |
| 6 | WebSocket (GPS/chat) not audited | 🟠 HIGH | audit.gps_updates + audit.chat_events batch insert |
| 7 | Audit log missing status code | 🟠 HIGH | extend audit middleware to capture response status |
| 8 | Audit log missing body/old-new value | 🟠 HIGH | hash request body + hash old/new for mutations |
| 9 | /internal/push has no auth | 🟠 HIGH | service-JWT (sub="booking-service", separate SERVICE_JWT_SECRET) |
| 10 | No CSRF token (web) | 🟡 MEDIUM | X-CSRF-Token middleware on state-changing endpoints |
| 11 | Audit doesn't cover reads | 🟡 MEDIUM | opt-in audit GET on sensitive admin endpoints |
| 12 | PIN hash no salt | 🟡 MEDIUM | per-device salt + Argon2 |
| 13 | WS in-app message rate limit | 🟡 MEDIUM | verify 1/sec GPS drop works (v1 code at tracking/handlers.rs:54-55 — port to presence) |
| 14 | No secret rotation policy | 🟡 MEDIUM | quarterly rotation, Vault for prod |
| 15 | Presigned URL cache stale (403 after 1hr) | 🟡 MEDIUM | mobile Cache-Control + 403 → reload pattern |

Verify against this list on every security-touching merge.
