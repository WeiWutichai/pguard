# 03 · Security Posture

ย้อนกลับ → [02 Issues](02-issues.md) · ถัดไป → [04 Tests](04-tests.md)

> หมายเหตุ: ระบบนี้ผ่าน security hardening มาหลายรอบ (commit 016cd6f, security hotfix C1 ฯลฯ) — **พื้นฐานแข็งแรง**. รายงานนี้เน้น **gap ที่เหลือเทียบ best-practice 2026** เพื่อ v2

---

## 3.1 สิ่งที่ทำถูกแล้ว (Baseline ที่ดี)

| Control | ยืนยันที่ | สถานะ |
|---|---|---|
| JWT `aud` validation (`guard-dispatch`) | shared/auth.rs | ✅ active (016cd6f) |
| JWT `exp` validation | jsonwebtoken default | ✅ |
| jti revocation blocklist (Redis `revoked_jti:{jti}`) ทุก request | shared/auth.rs AuthUser extractor | ✅ |
| JWT key caching (pre-computed encoding/decoding key) | shared/config.rs JwtConfig | ✅ |
| Refresh rotation atomic (single UPDATE…WHERE…RETURNING) | auth/handlers.rs | ✅ |
| Session limit 5/user (evict oldest) | auth/service.rs login | ✅ |
| Argon2 ใน `spawn_blocking` | auth/service.rs hash_password | ✅ |
| Mobile/Web login isolation (/login/phone cookie vs /login/mobile body) | — | ✅ |
| Magic-byte validation (JPEG/PNG/WEBP/MP4/QT) ก่อน size | auth + chat service | ✅ |
| CORS env-driven (ไม่ permissive) | shared/config.rs build_cors_layer | ✅ |
| Audit middleware ครบ 5 service (validate JWT signature จริง) | shared/audit.rs | ✅ |
| Presigned URL host rewrite + เก็บ S3 key (ไม่ใช่ signed URL) | auth finalize_avatar_url | ✅ |
| OTP: constant-time compare, atomic SET NX EX, daily cap TTL recovery | shared/otp.rs | ✅ |

---

## 3.2 JWT / Session Gaps (เทียบ best-practice 2026)

| Gap | สถานะปัจจุบัน | ความเสี่ยง | แก้ |
|---|---|---|---|
| **Force-revoke-all-tokens ไม่มี** | blocklist เป็น per-token (jti) เท่านั้น — admin revoke ทุก session ของ user ที่ถูก compromise ไม่ได้ | account takeover → token ที่ขโมยไปใช้ได้จนหมดอายุ refresh (สูงสุด ~7 วัน) | `token_revocation_version INT` ใน `auth.users`, increment เมื่อ revoke-all, เทียบทุก decode (1 Redis GET) |
| **Refresh reuse detection ไม่มี** | rotation atomic แต่ไม่ track lineage — refresh ที่ถูกขโมยใช้ซ้ำได้โดยไม่ถูกตรวจจับ | token theft ไม่ทริกเกอร์ revoke chain | RFC 6749 §6 rotation chain: `family_id` + `rotation_id`; ใช้ rotation เก่าซ้ำ → revoke ทั้ง family + alert |
| **Internal endpoint ไม่มี auth** | `/internal/push` (booking→notification) อาศัย network isolation อย่างเดียว | ถ้า Docker network ถูกเจาะ (เช่น mediasoup ถูก compromise) → spam notification | service-JWT (`sub="booking-service"`, secret แยก `SERVICE_JWT_SECRET`) |
| **mTLS ระหว่าง service ไม่มี** | trust ใคร ๆ ที่มี JWT valid บน network เดียวกัน | lateral movement หลัง breach | deferred v2.x (ต้องมี cert rotation infra) |
| **Token binding / DPoP ไม่มี** | token ไม่ผูก device/IP/key | token leak = full impersonation | optional DPoP สำหรับ enterprise tier |
| **PIN: SHA-256 ไม่มี salt + ไม่มี local rate limit** | `PinLoginScreen` ยิง `/auth/login/mobile` ตรง — ป้องกันแค่ nginx 5r/s. 6-digit = 1M, SHA-256 crack <1s ถ้าได้ hash | physical access (rooted) crack PIN; brute force ~55 ชม. **single IP** / **~1 ชม. distributed 50 IPs** (50 × 5r/s = 250 req/s → 1M ÷ 250 ≈ 67 นาที) | per-device salt + ย้าย validate ไป backend + nginx limit `/login/mobile` เป็น 3r/m |
| **iOS Keychain persist ข้าม uninstall** | PIN hash ค้างหลัง uninstall → reinstall ปลดล็อกได้ | บัญชีที่ถูก compromise ยังปลดล็อกผ่าน PIN เก่า | server-side compromise flag → force re-OTP (มี check-status บางส่วนแล้ว) |

---

## 3.3 Rate Limiting Completeness

### Zones ที่มี (nginx.conf)
| zone | rate | ครอบคลุม |
|---|---|---|
| auth_limit | 5r/s | `/auth/*` |
| otp_limit | 3r/m | `/auth/otp/*` |
| api_limit | 30r/s | `/booking/`, `/tracking/`, `/notification/`, `/chat/` |
| ws_limit | 5r/s | `/ws/track`, `/ws/chat` (upgrade) |
| swagger_limit | 10r/s | `/swagger-ui`, `/api-docs`, `/docs` |

### Gaps
| endpoint | ปัจจุบัน | ความเสี่ยง | แก้ |
|---|---|---|---|
| `/minio-files/*` | **ไม่มี limit** | enumerate/exfil S3 file ไม่จำกัด | `s3_limit 10r/s` |
| `/booking/admin/*` | api_limit 30r/s (เท่า public) | admin list (refunds/payments) ถูก DoS ที่ 30r/s | `admin_limit 5r/s` แยก |
| `POST /chat/attachments` | api_limit 30r/s | spam 30 upload/s × 200MB = disk/bw DoS | upload-specific limit + per-user daily quota |
| `POST /booking/payments` | api_limit 30r/s | ไม่มี per-user daily cap | Redis token-bucket per user (เช่น 10/วัน) |
| **WS message rate (in-app)** | nginx limit แค่ตอน upgrade | guard authenticated spam 1000 GPS msg/s = CPU DoS (มี heartbeat limit แต่ GPS update เอง?) | ตรวจ `handle_gps_socket` ว่า 1/sec drop ทำงานจริง |

### ปัญหาเชิงสถาปัตยกรรม
- **rate limit อยู่ที่ nginx edge เท่านั้น** — ไม่มี application-layer limit. ถ้า nginx ถูก bypass (เข้า service ตรงบน Docker network) = ไม่มีอะไรกั้น
- IP-based ผ่าน `X-Real-IP`/`X-Forwarded-For` — spoofable ถ้า attacker เข้าถึง header

> **v2:** เพิ่ม Redis-based token bucket per user_id ที่ application layer สำหรับ endpoint สำคัญ (payment, otp, upload)

---

## 3.4 Audit Log Gaps

### เก็บอะไร (shared/audit.rs)
`user_id`, `ip_address` (X-Real-IP → X-Forwarded-For), `entity_type` (path segment แรก), `action` (method+path), `timestamp`, `user_role`

### ไม่เก็บ (gap)
| ไม่เก็บ | ผลกระทบ |
|---|---|
| **request body** | ไม่รู้ว่า customer ขออะไร / admin อนุมัติค่าอะไร |
| **response status code** | แยก success (200) จาก error (400/500) ไม่ได้ |
| **old/new value (mutation)** | UPDATE ไม่มี before/after → ไม่มี change trail |
| **WebSocket events** | GPS update + chat message **ไม่ถูก audit เลย** |
| **GET / reads** | data exfiltration attempt ตรวจไม่ได้ |
| **correlation ID** | ตาม log ข้าม service ไม่ได้ |

### ปัญหา delivery
- audit เป็น **fire-and-forget `tokio::spawn`** → crash หลังส่ง response แต่ก่อน persist = action หาย
- ไม่มี separation of duties — admin อ่าน audit ของ action ตัวเองได้ (audit reader = writer)

### ความเสี่ยง repudiation (ตัวอย่างจริง)
- **ข้อพิพาทค่าจ้าง:** guard อ้างทำ 6 ชม. / customer อ้าง 2 ชม. → audit มีแค่ "PUT review-completion" ไม่มี actual_hours/decision → ต้อง manual review
- **GPS fraud:** guard ส่งพิกัดปลอม (อยู่บ้านแต่รายงานที่ทำงาน) → ไม่มี audit GPS → พิสูจน์ไม่ได้
- **Admin takeover:** อนุมัติ 100 applicant/นาที → audit ไม่มี IP change/device fingerprint/approval transition

> **v2:** เพิ่ม `audit.gps_updates`, `audit.chat_events` (batch insert), เพิ่ม status_code + body hash + old/new hash ใน `audit.logs`, audit GET สำหรับ sensitive admin endpoints

---

## 3.5 Other

| ด้าน | สถานะ | gap |
|---|---|---|
| Web cookie auth (httpOnly+Secure+SameSite=Lax) | ✅ | **ไม่มี CSRF token** — SameSite=Lax ไม่พอกัน cross-origin fetch บางกรณี → เพิ่ม `X-CSRF-Token` |
| localStorage JWT | ✅ ไม่ใช้ (ตรวจ frontend/web ยืนยัน 0 matches) | — |
| Docker non-root | ✅ (CLAUDE.md enforce) | ควรสแกน Trivy/Hadolint ยืนยันจริง |
| Secrets (GitHub Actions) | ✅ ไม่ hardcode | ไม่มี rotation policy; `.env.example` ไม่ enforce strength |
| File magic-byte | ✅ | video ตรวจแค่ `ftyp` ไม่ตรวจ codec (HEVC อาจ decode ไม่ได้) — มี history Huawei HW decoder bug |

---

## 3.6 Top Security Risks (จัดอันดับสำหรับ v2)

| อันดับ | ความเสี่ยง | ระดับ | ไฟล์ | แก้ |
|---|---|---|---|---|
| 1 | ไม่มี force-revoke-all-tokens (account compromise) | 🔴 CRITICAL | shared/auth.rs, auth/handlers.rs logout | `token_revocation_version` ใน auth.users |
| 2 | PIN brute-force (ไม่มี rate limit บน PinLoginScreen) — **~55 ชม. single IP / ~1 ชม. distributed 50 IPs** | 🔴 CRITICAL | mobile pin_login_screen.dart, /login/mobile | ย้าย validate ไป backend + nginx 3r/m + per-device salt |
| 3 | Refresh reuse detection ไม่มี | 🔴 CRITICAL | auth/service.rs refresh | rotation chain RFC 6749 |
| 4 | `/minio-files/` ไม่มี rate limit (exfil DoS) | 🟠 HIGH | nginx.conf | `s3_limit 10r/s` |
| 5 | admin endpoint rate เท่า public | 🟠 HIGH | nginx.conf | `admin_limit 5r/s` |
| 6 | WebSocket (GPS/chat) ไม่ถูก audit | 🟠 HIGH | tracking/chat handlers | audit.gps_updates / chat_events |
| 7 | audit ไม่เก็บ status code | 🟠 HIGH | shared/audit.rs | เพิ่ม status_code |
| 8 | audit ไม่เก็บ body / old-new value | 🟠 HIGH | shared/audit.rs | body hash + change hash |
| 9 | internal endpoint ไม่มี auth | 🟠 HIGH | notification /internal/push | service-JWT |
| 10 | ไม่มี CSRF token (web) | 🟡 MEDIUM | frontend/web + shared/config | X-CSRF-Token middleware |
| 11 | audit ไม่ครอบ read | 🟡 MEDIUM | shared/audit.rs | opt-in audit GET (admin) |
| 12 | PIN hash ไม่มี salt | 🟡 MEDIUM | mobile pin_storage_service | per-device salt |
| 13 | WS message rate limit (in-app) | 🟡 MEDIUM | tracking handler | 1/sec drop |
| 14 | ไม่มี secret rotation | 🟡 MEDIUM | deploy.yml | quarterly rotation runbook |
| 15 | presigned URL cache ไม่ refresh (403 หลัง 1 ชม.) | 🟡 MEDIUM | mobile api_client | Cache-Control + 403 reload |

---

ถัดไป → [04 Test Coverage Gap](04-tests.md)
