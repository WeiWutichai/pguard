# 02 · Architectural Issues

ย้อนกลับ → [01 Current State](01-current-state.md) · ถัดไป → [03 Security](03-security.md)

---

## 2.1 Coupling Problems

### C1 — Cross-schema direct writes (รากของ coupling)
booking เขียนตรงเข้า schema ที่ตัวเองไม่ได้เป็นเจ้าของ:
- `notification.notification_logs` (10 sites ผ่าน `spawn_notification`)
- `chat.messages` (3 sites — call event records, BUG-038)

**ผลกระทบ:**
- เปลี่ยน schema ของ notification/chat → ต้องแก้ booking ด้วย (hidden compile-time coupling เพราะใช้ `sqlx::query` runtime, error จะโผล่ตอน runtime ไม่ใช่ build)
- ไม่มี single source of truth ว่า notification ถูกสร้างอย่างไร — logic กระจายใน booking + chat + notification
- Test ยาก: ต้อง spin up หลาย schema เพื่อทดสอบ booking flow เดียว

**ทางแก้ v2:** event-driven (booking emit `assignment.accepted` event → notification service subscribe) หรืออย่างน้อย authenticated REST ingress (`POST /notifications` ที่ notification เป็นเจ้าของ logic)

### C2 — booking เป็น hub ของทุกอย่าง
booking ถือ assignment + payment + review + call + discovery → ทุก service อื่นต้องอ้างอิง booking. การแก้ payment เสี่ยงกระทบ call signaling เพราะอยู่ไฟล์เดียวกัน (`service.rs`)

### C3 — Flutter provider coupling
- `AuthProvider` (888 LOC) เป็น god-provider: registration orchestration (`registerWithOtp → updateRole → submitGuardProfile`), profile fetch, role switching, token lifecycle รวมกัน
- `BookingProvider` พึ่ง `AuthProvider.phone` ที่อาจ `null` (fragile)
- `TrackingProvider.toggle()` ถูกเรียกทั้งจาก UI และ provider init → race window

---

## 2.2 Single Points of Failure (SPOF)

| SPOF | ผลกระทบ | ความรุนแรง |
|---|---|---|
| **PostgreSQL เดียว** (guard_dispatch_db) | ทุก 6 service ใช้ร่วม → DB ล่ม = ทั้งระบบล่ม. ไม่มี read replica, ไม่มี sharding. 6 pool × 20 conn = สูงสุด 120 conn ชนตัวเดียว | 🔴 สูง |
| **nginx เดียว** (เป็น ingress เดียว) | nginx ล่ม = เข้าระบบไม่ได้เลย. ไม่มี LB หลายตัว | 🟠 กลาง |
| **Redis cache / pubsub** | cache ล่ม = JWT revocation check fail (fail-open หรือ fail-closed?), OTP rate limit หาย; pubsub ล่ม = GPS map miss frame (มี log-and-continue) | 🟠 กลาง |
| **notification fire-and-forget** | ถ้า notification service ล่ม booking ยัง commit ได้ แต่ push ไม่ออก + ไม่มี retry queue → notification หาย | 🟡 ต่ำ-กลาง |
| **mediasoup เดียว** | call ทั้งระบบผ่าน SFU ตัวเดียว | 🟡 ต่ำ |

> **ไม่มี distributed transaction:** ถ้า booking INSERT notification สำเร็จแต่ HTTP push fail → log มีแต่ push ไม่ออก (inconsistency เงียบ ๆ)

---

## 2.3 Missing Abstractions

| Abstraction ที่ขาด | ผลที่ตามมา | ข้อเสนอ v2 |
|---|---|---|
| **Event bus / message queue** | notification เป็น direct INSERT, ไม่มี retry/replay, ไม่มี fan-out | NATS / Redis Streams / Kafka — booking emit domain events |
| **Notification เป็น event-driven** | 10 call sites hardcoded ใน booking | subscribe-based: service ใดก็ publish event ได้ |
| **Service-to-service auth layer** | `/internal/push` ไม่มี token | shared service-JWT (`sub="booking-service"`) |
| **Domain layer แยกจาก transport** | business logic ปนใน handler/service.rs ก้อนเดียว | แยก `domain/` (pure logic, testable) ออกจาก `api/` |
| **Flutter: countdown/progress เป็น service** | math อยู่ใน screen, ซ้ำ 2 หน้า, test ไม่ได้ | `CountdownController` / `ProgressReportManager` |
| **Flutter: WebSocket abstraction** | `_connectAssignmentWs()` อยู่ใน screen | `AssignmentSocketService` ใน service layer |
| **Outbox pattern** | cross-schema write ไม่ atomic กับ business tx | transactional outbox → relay |

---

## 2.4 State Management Leak / Tight Coupling

### Backend
- business logic (proration, status machine, Haversine) ฝังใน `service.rs` ก้อนเดียว — ไม่มี domain layer แยก ทำให้ unit test ต้องแตะ DB

### Flutter (ปัญหาหลัก)
**Business logic รั่วเข้า screen:**
- `active_job_screen.dart:_calcRemainingFromStartedAt()` — countdown math ใน UI (ซ้ำใน customer version)
- `active_job_screen.dart:_checkHourBoundary()` (~40 LOC) — hour-boundary detection ผูกกับ `_lastCheckedHour`, `_isReportDialogOpen`, `_missedHours` (UI state) → unit test ไม่ได้
- `booking_provider.dart:fetchJobs()` — client-side status filtering (hardcode enum string 7 ค่า) → coupling กับ backend enum

**REST polling แทน push (จุดเปราะที่สุด):**

| screen | endpoint | interval | timers |
|---|---|---|---|
| active_job (guard) | /guard/active-job | 30s resync + 3s pending | 2 + WS |
| customer_active_job | /assignments/{id} | 3s | 1 (ไม่มี WS!) |
| customer_tracking | /assignments/{id} | 5s status + 5s location | 2 |
| waiting_for_guard | /assignments/{id} | 5s | 1 |
| guard_job_detail | (provider) | implicit | WS |

→ กรณีแย่สุด ~13 concurrent poll timers. BUG-016/021 ทั้งหมดเป็น **race ระหว่าง poll กับ WS** หรือ stale state. customer-side status change (guard accept/decline/complete) ยังใช้ REST polling ไม่มี WebSocket

> **นี่คือเหตุผลหลักที่ควรย้ายไป push-based ใน v2** — ตัด race condition class ทั้งหมดออก

---

## 2.5 Database — N+1 / Index Gaps

### N+1 / inefficient queries

**`chat/service.rs:181` list_conversations** — nested scalar subquery ต่อ row:
- `last_message`, `last_message_at`, `participant_name`, `unread_count` ต่างเป็น subquery รันต่อ conversation
- ผู้ใช้มี 100 conversation → 400+ subquery
- **แก้:** `LEFT JOIN LATERAL (... ORDER BY created_at DESC LIMIT 1)` + JOIN read_receipts ครั้งเดียว

**`booking/service.rs:3825` list_available_guards** — Haversine คำนวณซ้ำ 2 ครั้ง (WHERE clause line 3842-3847 และ 3879-3884). ไม่ใช่ N+1 แต่ duplicate computation + อ่านยาก
- **แก้:** CTE คำนวณ distance ครั้งเดียว

### Index gaps
| ตาราง | index ที่ควรมี | ใช้โดย |
|---|---|---|
| `notification.notification_logs` | `(user_id, sent_at DESC)` | list_notifications, unread-count — **ไม่มี index บน user_id** |
| `booking.assignments` | `(request_id, guard_id)` composite | `is_guard_assigned()` (CLAUDE.md ระบุว่าควรมี — ตรวจว่ามีจริงใน migration หรือยัง) |
| `booking.guard_requests` | `(status, created_at DESC)` | list_requests |

> CLAUDE.md ระบุ performance index เหล่านี้เป็น convention แต่ควร **ตรวจ migration จริงว่าถูกสร้างครบ** — เป็นการบ้านก่อน v2 load test

---

## 2.6 สรุป Issues จัดอันดับ

| # | Issue | หมวด | ความรุนแรง | แก้ใน v2 |
|---|---|---|---|---|
| 1 | booking god-service (5 domain/ไฟล์เดียว) | maintainability | 🔴 | แตก service |
| 2 | cross-schema direct write (booking→notification/chat) | coupling | 🔴 | event bus / REST ingress |
| 3 | REST polling race (Flutter, BUG cluster) | reliability | 🔴 | push/WebSocket |
| 4 | PostgreSQL SPOF | availability | 🟠 | read replica / connection pooling (pgbouncer) |
| 5 | business logic ใน Flutter screens | testability | 🟠 | extract controller/service |
| 6 | auth god-service (4 flow ปน) | maintainability | 🟠 | แตก module |
| 7 | N+1 list_conversations | performance | 🟡 | rewrite JOIN |
| 8 | index gap (notification_logs) | performance | 🟡 | add index |
| 9 | ไม่มี event/outbox/retry | reliability | 🟡 | outbox pattern |
| 10 | god-object screens (2.3K LOC) | maintainability | 🟡 | แตก widget |

---

ถัดไป → [03 Security Posture](03-security.md)
