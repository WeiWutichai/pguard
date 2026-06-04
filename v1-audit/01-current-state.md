# 01 · Current State Analysis

ย้อนกลับ → [Overview](00-overview.md) · ถัดไป → [02 Issues](02-issues.md)

---

## 1.1 Service Boundaries

| Service | Port | LOC | Endpoints | ความรับผิดชอบ | สถานะ |
|---|---|---|---|---|---|
| **shared** | — | 2,046 | (lib) | JWT, config, error, models, otp, sms, audit, openapi | OK |
| **auth** | 3001 | 9,549 | ~27 | JWT/OTP/login flows, user+guard+customer profiles, document upload, admin approval | 🔴 บวม (service.rs ~3,400 LOC) |
| **booking** | 3002 | 9,394 | ~49 | requests, assignments, payments, pricing, reviews, calls (C2), progress reports, admin wallet | 🔴 บวมสุด (service.rs ~5,400 LOC) |
| **tracking** | 3003 | 1,003 | 4 | GPS WebSocket, location history, location queries | 🟢 lean |
| **notification** | 3004 | 1,098 | 7 + internal | FCM token, notification logs, push delivery | 🟢 lean |
| **chat** | 3006 | 2,428 | 8 | chat WebSocket, conversations, messages, attachments (MinIO) | 🟡 ปานกลาง |
| mediasoup | 3005 | (Node) | — | video/audio call SFU | ข้อยกเว้น (ไม่ใช่ Rust) |

### ทำไม booking/auth ถึงบวม

**booking/service.rs (~5,400 LOC)** รวม 5 domain ในไฟล์เดียว:
- Request lifecycle + assignment state machine — ฟังก์ชัน `update_assignment_status()` ยาว ~290 LOC, branch 4 ทาง, side-effect ข้าม DB/Redis/notification
- Payment ledger — `create_payment`, `prorate_payment_in_tx` (~110 LOC), `add_tip`, admin refund workflow (migration 042)
- Reviews + visibility
- Call signaling (C2) — `initiate/accept/reject/end_call` + WS (~300 LOC ที่ควรเป็น service แยก)
- Guard discovery — `list_available_guards()` (~75 LOC, 5 JOIN + Haversine ซ้ำ 2 ครั้ง)

**auth/service.rs (~3,400 LOC)** รวม:
- 4 auth flow (email/password, phone/OTP, phone/PIN-hash, role-select) พันกัน
- Dual approval tracking (users vs customer_profiles)
- Document upload (10MB validation, magic bytes, S3, watermark "FOR SECURITY USE ONLY")
- OTP/SMS ผสมกับ user registration

---

## 1.2 Cross-Service Coupling

### booking → notification (direct INSERT) — anti-pattern หลัก
`services/booking/src/service.rs` มี helper `spawn_notification()` (lines 92–152) ที่ `tokio::spawn` แล้ว **INSERT ตรงเข้า `notification.notification_logs`** (line 104) + ยิง HTTP ไป `http://rust-notification:3004/internal/push`.

**10 call sites:**

| # | line | trigger | แจ้งใคร |
|---|---|---|---|
| 1 | 506 | `cancel_request()` | guard: "งานถูกยกเลิก" |
| 2 | 594 | `assign_guard()` | guard: "งานใหม่ที่ได้รับ" |
| 3 | 882 | accept | customer: "เจ้าหน้าที่ตอบรับ" |
| 4 | 1941 | en_route | customer: "กำลังเดินทาง" |
| 5 | 1955 | arrived | customer: "ถึงแล้ว" |
| 6 | 2062 | decline | customer: "เจ้าหน้าที่ปฏิเสธ" |
| 7 | 3555 | `add_tip()` | guard: "ลูกค้ามอบทิป" |
| 8 | 3672 | `review_completion()` approve | guard: "งานเสร็จสมบูรณ์" |
| 9 | 4857 | `reject_call()` | caller: "สายถูกปฏิเสธ" |
| 10 | 5024 | `end_call()` | คู่สนทนา: "วางสาย" |

### booking → chat.messages (direct INSERT)
booking เขียน record "call ended/rejected/finished" ลง `chat.messages` ที่ `service.rs:5037, 5089` (BUG-038). chat service เป็นเจ้าของ schema นี้ → ความรู้เรื่อง "สายจบเมื่อไหร่" กระจายอยู่ 2 service

### ช่องทางสื่อสารระหว่าง service

| รูปแบบ | จาก → ไป | ช่องทาง |
|---|---|---|
| Direct DB write | booking → notification, booking → chat | PostgreSQL INSERT (cross-schema) |
| HTTP internal | booking → notification | `http://rust-notification:3004/internal/push` (**ไม่มี token auth** — network isolation อย่างเดียว) |
| Redis PubSub | booking ↔ chat (assignment status), tracking (GPS frames) | Redis pub/sub |
| ไม่มี | tracking ↔ auth | tracking แค่ SELECT `auth.users.full_name` |

> ไม่มี HTTP API call ระหว่าง service แบบ authenticated, ไม่มี gRPC, ไม่มี message queue/event bus

---

## 1.3 Data Ownership Matrix

| Schema | เจ้าของ (write) | ผู้อ่าน | shared write ผิดปกติ |
|---|---|---|---|
| **auth** | auth | ทุก service (SELECT) | — ✅ |
| **booking** | booking | booking, chat, tracking (FK) | — ✅ |
| **tracking** | tracking | booking (available-guards) | — ✅ |
| **notification** | notification | (ใช้ภายใน) | ⚠️ **booking INSERT ตรง** |
| **reviews** | booking | booking (admin) | — ✅ (booking เป็นเจ้าของ assignment) |
| **chat** | chat | chat, booking (call record) | ⚠️ **booking INSERT call event** |
| **audit** | ทุก service (middleware) | admin (อ่าน) | ✅ (append-only, ออกแบบมาให้เป็นแบบนี้) |

**สรุป anti-pattern:** มี 2 จุดที่ service เขียน schema ที่ตัวเองไม่ได้เป็นเจ้าของ — ทั้งคู่มาจาก booking (→ notification, → chat). เป็นรากของ coupling ที่ควรแก้ด้วย event-driven / REST ingress ใน v2

---

## 1.4 Tech Debt Hotspots

### `unwrap()` / `expect()`
- grep รวม ~92 matches ใน prod path — **แต่จากการอ่านจริง** ส่วนใหญ่อยู่ใน:
  - auth cookie parsing (`.expect()` บน hardcoded string — startup-safe): `auth/handlers.rs:37,46,55,451,453,456`
  - HTTP client builder ตอน startup: `booking/main.rs`, `notification/main.rs`
  - test modules
- **request-handling path ที่อันตรายจริง: ~0** (tracking + chat สะอาด 0 unwrap)
- ✅ ยังควรกวาดล้างใน v2 เพื่อให้ผ่าน hook `unwrap check` แบบ strict

### TODO/FIXME
- มีเพียง **3** ใน Rust (ต่ำมาก — housekeeping ดี). ไม่มี TODO ค้างใน critical path

### BUG-XXX comments (58 รวมทั้ง repo)

**Backend (Rust):**
| ไฟล์ | จำนวน | ตัวอย่าง |
|---|---|---|
| booking/service.rs | 5 | BUG-011 (notify cancelled guards), BUG-013 (guard name via JOIN), BUG-038 (call record in chat) |
| booking/models.rs | 3 | BUG-013 (customer_name เฉพาะ get_request), BUG-015 Issue B (location_lat/lng) |
| chat/handlers.rs, chat/service.rs | 2 | BUG-025 (video attachment notification missing) |

**Mobile (Flutter) — หนาแน่นที่สุด:**
| ไฟล์ | จำนวน | สิ่งที่บ่งชี้ |
|---|---|---|
| customer_tracking_screen.dart | 8 | BUG-017 (map zoom cap), BUG-021 (status progression race ผ่าน arrived) |
| guard_job_detail_screen.dart | 8 | BUG-014 (cancellation watchdog), BUG-015 (status sync lag) |
| booking_provider.dart | 5 | BUG-003 (stale guard busy badge — IndexedStack ไม่ re-init) |
| active_job_screen.dart | 3 | BUG-016 (null = terminal signal จาก backend filter) |

> **Pattern สำคัญ:** BUG cluster กระจุกที่ **polling/WebSocket race + stale local state** — ยืนยันว่า REST-polling architecture เป็นจุดเปราะ (ดู [02](02-issues.md) §2.4)

### ฟังก์ชันซับซ้อนสุด (candidate สำหรับแตกใน v2)
| ฟังก์ชัน | ไฟล์ | LOC | หมายเหตุ |
|---|---|---|---|
| `update_assignment_status()` | booking/service.rs:615 | ~290 | state machine 4 ทาง + notification + redis + Haversine |
| `submit_progress_report()` | booking/service.rs:3919 | ~120 | file upload + S3 multipart + transcode |
| `review_completion()` | booking/service.rs:3578 | ~130 | transaction + proration ใน tx เดียว |
| `list_available_guards()` | booking/service.rs:3825 | ~75 | 5 JOIN + Haversine คำนวณซ้ำ 2 ครั้ง (3842-3847 และ 3879-3884) |
| `list_conversations()` | chat/service.rs:181 | ~50 | nested subquery ต่อ row (N+1 risk) |

---

## 1.5 Frontend Duplication (Flutter)

### หน้าซ้ำ/orphaned ที่ลบได้ทันที (~600 LOC)
| ไฟล์ | LOC | สถานะ |
|---|---|---|
| `set_password_screen.dart` | ~200 | **dead** — comment ระบุ "no longer in main registration flow" |
| `registration_role_screen.dart` | ~300 | **dead** — ถูกแทนด้วย `role_selection_screen.dart` |
| `customer_login_screen.dart` | ~100 | **dead** — mobile ใช้ `loginWithPhone()` รวมศูนย์แล้ว |

### หน้าซ้ำเชิงตรรกะ (ควร consolidate)
| คู่ | ปัญหา |
|---|---|
| `guard_registration_screen.dart` (top-level, 1,381 LOC) vs `guard/guard_registration_screen.dart` (1,181 LOC) | **มี 2 ไฟล์ชื่อเดียวกัน** interface ต่างกัน — top-level รับ profileToken+initialProfile |
| `guard/active_job_screen.dart` (2,293 LOC) vs `hirer/customer_active_job_screen.dart` (1,540 LOC) | countdown math, `_formatTime()`, `_pollStatus()` ซ้ำ ~80% — debug `_debugTickAmount=120` ต้อง sync มือ |
| `hirer/customer_tracking_screen.dart` (1,063) vs `guard/guard_navigation_screen.dart` (~800) | map setup + `CameraFit.bounds(maxZoom:16)` + marker ซ้ำ |
| `hirer_history_screen.dart` (930) vs `receipt_list_screen.dart` (300) + `receipt_detail_screen.dart` (370) | ทั้งคู่แสดง "งานในอดีต" คนละมุม (สถานะ vs ใบเสร็จ) |

### Copy-paste widget
- **P-Guard green header** ซ้ำใน ~17 หน้า × ~70 LOC = **~1,190 LOC** — ไม่ถูก extract เป็น widget เดียว

### 5 ไฟล์ใหญ่สุด (god-objects)
| ไฟล์ | LOC | methods |
|---|---|---|
| guard/guard_job_detail_screen.dart | 2,361 | 25 |
| guard/active_job_screen.dart | 2,293 | 33 |
| hirer/booking_screen.dart | 2,008 | 25 |
| hirer/customer_active_job_screen.dart | 1,540 | 21 |
| hirer/hirer_history_screen.dart | 930 | 9 |

---

## 1.6 Legacy Code

- **Rust:** ไม่มี legacy/deprecated ฟังก์ชันค้างที่มีนัยสำคัญ (housekeeping ดี). มี BUG-XXX comment เป็น "scar tissue" แต่โค้ดยัง active
- **Flutter:** 3 orphaned screens (ข้างบน) + dead SharedPreferences keys (`guard_registered`/`customer_registered` ที่เขียนแต่ไม่ถูกอ่าน หลังเลิกใช้ `isRegistered()`) + legacy migration code ใน `auth_service.dart` (อ่าน phone จาก SharedPreferences เก่า → secure storage) ที่ยัง backward-compat
- **Env:** `JWT_EXPIRY_HOURS` deprecated → `JWT_EXPIRY_MINUTES`; pricing `min_price/max_price/price_per_hour` ถูกลบ (migration 037+038) เหลือ `base_fee` — DB สะอาดแล้ว
- **Web:** debt ต่ำ — ไม่มี route `/members` (รวมเข้า applicants), map status เหลือ 3 (ลบ "alert" gray)

---

ถัดไป → [02 Architectural Issues](02-issues.md)
