# 04 · Test Coverage Gap

ย้อนกลับ → [03 Security](03-security.md) · ถัดไป → [05 Recommendations](05-recommendations.md)

---

## 4.1 Backend Test Inventory

| Service | integration dir | inline `#[cfg(test)]` | ~test funcs | ประเมิน |
|---|---|---|---|---|
| **auth** | ✅ `tests/integration_tests.rs` (~45 funcs) | handlers.rs, service.rs | ~100 inline | 🟢 แข็งแรงสุด |
| **booking** | ❌ | service.rs เท่านั้น | ~54 inline | 🟡 validation ดี / **proration ไม่มี test** |
| **chat** | ❌ | s3.rs เท่านั้น | ~31 inline | 🟠 อ่อน (แค่ S3) |
| **tracking** | ❌ | **ไม่มี** | **0** | 🔴 วิกฤต |
| **notification** | ❌ | **ไม่มี** | **0** | 🔴 วิกฤต |
| **shared** | ❌ (lib) | otp, auth, error, config, models, sms | ~72 inline | 🟢 แข็งแรง |

รวม inline unit ~257 funcs + auth integration ~45 funcs

### สิ่งที่ inline test แต่ละตัวครอบคลุม
- **auth/service.rs (~94):** registration OTP flow, profile-token single-use, dual-auth (phone_verified_token vs Bearer), name merge, password length, session atomic. **ขาด:** session limit (5) enforcement, cross-service jti propagation
- **booking/service.rs (~54):** input validation (coords, hours, guard_count, price bounds ~30), payment amount>0 (~5), service rate bounds (~8), receipt numbering (~5), refund action validation (~6). **ขาดวิกฤต:** `compute_proration()` + `prorate_payment_in_tx()` = **0 test** (logic คิดเงินจริง!)
- **chat/s3.rs (~31):** presigned URL, object delete, metadata. **ขาด:** WS messaging, participant auth, read receipts
- **shared (~72):** OTP gen/validate, Thai phone, JWT encode/decode, error, CORS

---

## 4.2 Critical Path Coverage

### AUTH 🟢 ดีที่สุด
| path | สถานะ |
|---|---|
| login email/password | ✅ generic 401 shape tested |
| login mobile | ✅ tokens in body tested |
| JWT validation (alg none, wrong secret, wrong aud) | ✅ |
| JWT revocation (logout cross-service) | ✅ integration |
| refresh rotation (used token reject, concurrent only-one) | ✅ |
| OTP request (Thai format, bad challenge) | ⚠️ partial (happy path `#[ignore]` — ต้อง capture SMS) |
| OTP verify constant-time | ❌ skipped (timing flaky) |
| registration happy path | ⚠️ `#[ignore]` |

### PAYMENT 🟡 ช่องโหว่อันตราย
| path | สถานะ |
|---|---|
| create_payment amount≤0 reject | ✅ |
| payment method validation | ✅ |
| **proration math (clamp to booked_hours, refund calc)** | ❌ **0 test** — เงินจริง |
| **tip accumulation (tip += )** | ❌ 0 test |
| refund workflow (reference required) | ⚠️ validation เท่านั้น — state machine ไม่มี |
| cost-summary endpoint | ❌ 0 test |

### GPS 🔴 ไม่มีเลย
| path | สถานะ |
|---|---|
| `GpsUpdate::validate()` (lat/lng/accuracy bound, reject 0,0, NaN/Inf) | ❌ 0 test |
| set_online/set_offline transition | ❌ |
| rate limit 1/sec | ❌ |
| ping/pong zombie disconnect | ❌ |
| cleanup_old_history(90) | ❌ |

### AUTHORIZATION / IDOR 🔴 ช่องโหว่
| path | สถานะ |
|---|---|
| is_guard_assigned() | ❌ 0 test |
| has_active_booking() | ❌ |
| conversation participant check | ❌ |
| admin-only 403 branch | ⚠️ มีแต่ test 401, branch 403 `#[ignore]` |

---

## 4.3 Flutter Test Inventory (4 ไฟล์)

| ไฟล์ | ครอบคลุม |
|---|---|
| `pin_storage_service_test.dart` | 🟢 PIN rate limit (PinValid/Invalid/LockedOut/Wiped, wipe @ attempt 10) — แข็งแรง |
| `guard_registration_test.dart` (246 LOC) | 🟢 form validation (bank name match, account mask) |
| `thai_baht_text_test.dart` (40) | baht formatting (niche) |
| `widget_test.dart` (24) | placeholder |

### Flutter flows ที่ **ไม่มี test เลย**
OTP registration (3-step), booking creation/search, chat messaging (WS), GPS tracking, payment/cost-summary, active-job countdown/progress, AuthProvider state (login/logout/refresh/role switch)

---

## 4.4 Test Infrastructure

- **CI (`ci.yml`):** รัน `cargo test --workspace` ทุก push/PR ✅ — **แต่ Flutter test ไม่อยู่ใน CI** ❌
- **ไม่ hermetic:** auth integration test ต้องมี live postgres + redis + minio (Docker Compose) — ไม่มี embedded DB
- **ไม่ isolate:** test สร้าง phone/email ด้วย UUID suffix แต่ไม่ truncate → data สะสม
- **rate-limit retry:** test มี `send_retrying()` รับมือ nginx 503/429
- **mocking:** Flutter mock secure storage + SharedPreferences; backend ไม่มี mock DB (พึ่ง live Postgres)

---

## 4.5 Coverage Gap Matrix (จัดลำดับ v2)

### P0 — CRITICAL (security / core money/safety logic)
| Component | unit | integ | ความเสี่ยง | ทำ |
|---|---|---|---|---|
| GPS `GpsUpdate::validate()` | ❌ | ❌ | 🔴 | +20 unit (bounds, 0,0, NaN/Inf, range) |
| Payment proration `compute_proration` | ❌ | ❌ | 🔴 เงิน | +8 unit (clamp, refund, edge 0 ชม./exact) |
| Cross-service jti propagation | ✅(unit) | ⚠️(same svc) | 🟠 | +1 integ: logout @auth → 401 @booking/chat/tracking |

### P1 — HIGH (core features)
| Component | ความเสี่ยง | ทำ |
|---|---|---|
| tracking online/offline + ping/pong | 🟠 | unit |
| chat participant authorization | 🟠 IDOR | unit (role-based read) |
| notification FCM (register/list/unread) | 🟠 | สร้าง `notification/tests/` |
| tip accumulation | 🟠 เงิน | unit |
| IDOR (is_guard_assigned, has_active_booking) | 🟠 | integ 403 branches |

### P2 — MEDIUM
chat attachment upload (integ), refund state machine, session limit 5, location history cleanup, Flutter OTP registration widget test

### P3 — LOW
Flutter chat/booking UI golden, web admin map E2E (Playwright), mediasoup call setup

---

## 4.6 สรุปสำหรับ v2

**Blocking (ก่อน v2 launch):**
1. GPS validate tests (safety-critical)
2. Proration tests (money-critical — ตอนนี้ logic คิดเงินไม่มี test เลย)
3. Cross-service revocation integ test

**v2 infra:**
- แยก CI เป็น 2 job: unit (no Docker) + integration (`docker compose up`)
- เพิ่ม `flutter test` ใน CI
- `docker-compose.test.yml` แยก DB (กัน data สะสม)
- ตั้งเป้า coverage gate (เช่น 60% line สำหรับ service.rs ที่ถือ money/safety logic)

---

ถัดไป → [05 Recommendations for v2](05-recommendations.md)
