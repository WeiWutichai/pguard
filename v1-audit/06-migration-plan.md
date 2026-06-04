# 06 · Migration Plan (Phased)

ย้อนกลับ → [05 Recommendations](05-recommendations.md) · [กลับ Overview](00-overview.md)

---

## ภาพรวม

แผน **6 เฟส** แบบ strangler-fig — ระบบยังเป็น **dev/staging (ไม่มี production users)**, ใช้ strangler-fig เป็นวินัยกัน big-bang risk ไม่ใช่ข้อจำกัด user-availability ([05 §5.1](05-recommendations.md)). แต่ละเฟสส่งมอบคุณค่าได้เอง + deploy/rollback ได้, แต่ dual-write/fallback ทำเฉพาะที่ลด risk จริง. ลำดับออกแบบให้ **"ปูพื้นความปลอดภัย" (test + security) ก่อน "ผ่าตัดโครงสร้าง"** เพื่อให้มี safety net ตอนแตก service

```
Phase 0    Stabilize & Net      ── test + security quick-win + cleanup
Phase 0.5  Baseline & Compliance ── perf baseline + PDPA gap audit (no code change)
Phase 1    Decouple Notifications ── event bus + service-auth
Phase 2    Push-based Mobile     ── WebSocket แทน polling
Phase 3    Split booking         ── 4 service
Phase 4    Split auth + Flutter state ── module + Riverpod
Phase 5    Scale & Harden        ── pgbouncer, replica, observability, DPoP
```

> ใช้ **half-phase numbering (0.5)** จงใจ — กัน renumber ที่จะทำให้ cross-reference ในเอกสารอื่นเพี้ยน

> ระยะเวลาเป็นค่าประมาณเชิงสัมพัทธ์ (ปรับตามขนาดทีม) — ไม่ใช่ commitment

---

## Phase 0 — Stabilize & Safety Net 🟢 ต่ำ
**เป้า:** มี test + security baseline ก่อนแตะโครงสร้าง — "เซฟตี้เน็ตก่อนปีนสูง"

- [ ] **Test P0 ([04](04-tests.md)):** proration unit tests, `GpsUpdate::validate()` unit tests, cross-service jti revocation integration test
- [ ] **Security quick-win ([03](03-security.md) #4,#5,#13):** nginx `s3_limit` บน `/minio-files/`, `admin_limit 5r/s` บน `/booking/admin/*`, ยืนยัน WS 1/sec drop
- [ ] **CI:** แยก unit/integration job, เพิ่ม `flutter test`, `docker-compose.test.yml`
- [ ] **Cleanup:** ลบ 3 orphan screens (set_password, registration_role, customer_login), ลบ dead SharedPreferences keys, รวม `guard_registration_screen` 2 ไฟล์เป็น 1
- [ ] **Index audit:** ตรวจ migration ว่า `(user_id,sent_at)` บน notification_logs + composite indexes ครบ → เพิ่มด้วย `CREATE INDEX CONCURRENTLY`

**Exit criteria:** money/safety path มี test, CI เขียว 2 job, orphan ลบหมด
**Rollback:** ไม่มี structural change — revert ได้อิสระ

---

## Phase 0.5 — Baseline & Compliance 🟢 ต่ำ
**เป้า:** บันทึก baseline (perf + cost) + PDPA gap **ก่อนเปลี่ยนโค้ดใด ๆ** — read-only, ไม่มี code change. ตัวเลขที่ได้กลายเป็น "must not regress" gate ของทุก phase ถัดไป

- [ ] **Performance baseline (k6):** GPS WS frames/sec (N=10→1000), booking create p99, list_conversations p99 ที่ 100 conv/user, available-guards p99 ที่ radius 50 km, payment create p99, auth login (Argon2) p99 — บันทึกเลขปัจจุบัน
- [ ] **PDPA compliance audit:** data retention, right-to-erasure, data export, data-access audit (PDPA §30), data subject rights workflows → `07-pdpa.md`
- [ ] **Cost baseline:** infra cost/footprint ต่อ service ปัจจุบัน → `cost-baseline.md`

**Exit criteria:** baseline numbers documented, PDPA gap list พร้อม severity, cost report
**Rollback:** ไม่มี — read-only audit ล้วน

> ทุก phase ถัดไปเพิ่มเงื่อนไข exit: **"p99 ต้องอยู่ใน +20% ของ baseline"**

---

## Phase 1 — Decouple Notifications 🟠 สูง
**เป้า:** ลบ cross-schema write ([02](02-issues.md) C1) — รากของ coupling

- [ ] สร้าง `EventBus` trait ใน shared (NATS หรือ Redis Streams)
- [ ] notification svc: เพิ่ม `NotificationDispatcher` subscribe events + authenticated `POST /notifications` ingress + service-JWT บน `/internal/push`
- [ ] booking: เปลี่ยน 10 `spawn_notification` sites → emit event (**dual-write ช่วงเปลี่ยน:** เขียนทั้ง direct INSERT เดิม + emit event ใหม่, reconcile log)
- [ ] booking → chat call-event: ย้ายไป chat REST API (chat เป็นเจ้าของ)
- [ ] เพิ่ม transactional outbox (atomic business tx + event)
- [ ] ตัด direct INSERT เดิมออกเมื่อ event path proven

**Exit criteria:** notification 0 cross-schema write, event delivery มี retry, reconcile = 0 diff
**Rollback:** dual-write → ปิด event path, กลับ direct INSERT

---

## Phase 2 — Push-based Mobile 🟠 สูง
**เป้า:** ตัด BUG race class (BUG-016/021/...) — แทน REST polling ด้วย push

- [ ] `AssignmentSocketService` (Flutter) — WS lifecycle ออกจาก screen
- [ ] backend: assignment status → WebSocket/event push (มี Redis pubsub อยู่แล้วบางส่วน)
- [ ] customer_active_job + customer_tracking + waiting_for_guard: subscribe WS, **คง poll เป็น fallback** ระหว่าง rollout
- [ ] วัด: race-condition bug rate ลดลง, latency status change
- [ ] เมื่อ stable → ลด poll interval เป็น safety-net เท่านั้น (เช่น 30s)

**Exit criteria:** status change ผ่าน push <2s, BUG-016/021 class ปิด
**Rollback:** เปิด poll interval เดิมกลับ (fallback ยังอยู่)

---

## Phase 3 — Split booking 🔴 สูงสุด
**เป้า:** แตก god-service ([01](01-current-state.md) §1.1, [05](05-recommendations.md) §5.2)

**กลยุทธ์ 2 ขั้น (ลดความเสี่ยง):**
1. **Logical split ก่อน:** จัดระเบียบ `booking/src/` เป็น module `assignment/ payment/ rating/ call/` + `domain/ repo/ api/` layer (ยังเป็น binary เดียว) — characterization test ครอบทุก module
2. **Physical split ทีหลัง — ลำดับ `call → payment → rating → assignment`:**
   - **call-svc ก่อน** — isolated สุด (own DB tables, own state machine, ไม่มี FK ไป assignment นอกจาก `request_id`). หลัง Phase 1 เคลียร์ write ลง `chat.messages` (BUG-038) แล้ว call-svc มี zero cross-write → blast radius ต่ำสุด
   - **payment-svc สอง** — มี proration test จาก Phase 0 เป็น safety net. อ่าน `started_at` + `booked_hours` จาก assignment → ตอนแตก ให้ assignment-svc expose ค่าเหล่านี้เป็น read-only API
   - **rating-svc สาม** — เป็นเจ้าของ `reviews.guard_reviews` schema อยู่แล้ว → split ง่าย
   - **assignment-svc สุดท้าย** — เก็บส่วนที่เหลือ. ถึงตอนนี้อย่างอื่นถูกแยกออกไปหมดแล้ว

- [ ] Phase 0 proration tests = prerequisite
- [ ] แต่ละ service ใหม่: domain/repo/api layering, event-based ไม่ direct DB ข้าม

**Schema separation roadmap (3 ขั้น):**

**Step 3.1 — Schema-per-service ใน shared DB** (Phase 3 start)
- แต่ละ service ใหม่เป็นเจ้าของ schema ตัวเองเข้มงวด: `assignment-svc` เขียน `booking_assignments` schema เท่านั้น, `payment-svc` เขียน `booking_payments` เท่านั้น ฯลฯ
- Foreign key ข้าม schema คงไว้ชั่วคราวแต่ flag เป็น "boundary" — **ห้ามเพิ่ม cross-schema FK ใหม่**
- Read ข้าม schema ผ่าน direct SQL ได้ระหว่าง transition (ใช้ read-only role)

**Step 3.2 — แทน cross-schema read ด้วย API call** (Phase 3 mid)
- assignment-svc expose `GET /internal/assignments/{id}` ให้ payment-svc อ่าน `started_at`/`booked_hours`
- Service-JWT auth บน endpoint เหล่านี้ (ใช้ pattern จาก Phase 1)
- เพิ่ม caching ตามเหมาะสม

**Step 3.3 — DB-per-service** (Phase 5, หลัง stabilize)
- แต่ละ service ได้ Postgres database ของตัวเอง
- ลบ foreign key ข้าม service ทั้งหมด
- ยอมรับ eventual consistency ที่ business อนุญาต; transactional outbox สำหรับส่วนที่ต้อง consistent แน่นอน

**Exit criteria:** booking → 4 service deploy แยก, ไม่มี cross-write, test ต่อ service
**Rollback:** logical split revert ได้; physical split ใช้ feature flag route traffic (เก่า/ใหม่)

---

## Phase 4 — Split auth + Flutter state 🟠 สูง
**เป้า:** แตก auth god-service + ยกเครื่อง Flutter state

**Backend:**
- [ ] auth → module `auth-core / identity / documents / otp` (logical ก่อน, ใช้ integration test 45 funcs เป็น guard)
- [ ] เพิ่ม `token_revocation_version` (force-revoke-all) + refresh rotation chain ([03](03-security.md) #1,#3)

**Flutter:**
- [ ] migrate Provider → Riverpod **ทีละ feature** (เริ่ม notification/tracking ที่เล็กสุด → booking → auth ท้ายสุด)
- [ ] extract `CountdownController`, `ProgressReportManager`, `PGuardHeader` widget
- [ ] แยก registration orchestrator ออกจาก AuthProvider
- [ ] แตก god-object screens (active_job 2.3K → screen + widgets)

**Exit criteria:** auth modular, force-revoke ใช้ได้, Flutter feature ใช้ Riverpod + screens thin
**Rollback:** Flutter migrate ทีละ feature → revert เฉพาะ feature ที่มีปัญหา

---

## Phase 5 — Scale & Harden 🟡 กลาง
**เป้า:** เตรียมโตระดับเมือง/ประเทศ + security tier สูง

- [ ] **DB:** pgbouncer, read replica (route report/list), ตรวจ connection pool
- [ ] **Observability:** OpenTelemetry trace ข้าม service + correlation ID
- [ ] **Audit gaps ([03](03-security.md) #6,#7,#8,#11):** `audit.gps_updates` + `audit.chat_events` (batch), status_code + body/old-new hash ใน audit.logs, audit GET admin
- [ ] **Security tier:** CSRF token (web), per-device PIN salt, secret rotation runbook, optional DPoP/token binding
- [ ] **Secrets:** ย้าย Vault/Secrets Manager + quarterly rotation
- [ ] **Map:** เปลี่ยน tile provider เป็น commercial
- [ ] **Resilience:** mediasoup HA, nginx LB หลายตัว

**Exit criteria:** trace ครบ, audit ครอบ WS, scale test ผ่าน
**Rollback:** แต่ละ item independent — revert เฉพาะตัว

---

## ลำดับเฟส & เหตุผล

```
Phase 0 ──► 1 ──► 2 ──► 3 ──► 4 ──► 5
   │        │      │      │      │      └─ harden หลังโครงสร้างนิ่ง
   │        │      │      │      └─ auth ปลอดภัยกว่า booking (test มีอยู่) ทำหลังพิสูจน์ pattern กับ booking
   │        │      │      └─ แตก booking ต้องมี event (P1) + test (P0) + push (P2) พร้อมก่อน
   │        │      └─ push ตัด bug ก่อนผ่าตัด ลด noise
   │        └─ decouple ก่อนแตก (ไม่งั้นแตกแล้ว cross-write ยังพันกัน)
   └─ test + security net ต้องมาก่อนทุกอย่าง
```

**กฎเหล็ก:**
- ห้ามแตก service (Phase 3-4) ก่อนมี test + event bus (Phase 0-1)
- dual-write/fallback **เฉพาะจุดที่ลด risk จริง** (ไม่ใช่ทุกจุด — ดู [05 §5.1](05-recommendations.md)) — reconcile แล้วค่อยตัดของเก่า
- 1 เฟส = deploy ได้ + rollback ได้เอง — ไม่มีเฟสที่ "ต้องทำเสร็จทั้งหมดถึงจะ deploy"

---

## Definition of Done (v2)
- [ ] ไม่มี cross-schema direct write
- [ ] booking + auth ไม่ใช่ god-service
- [ ] booking status เป็น push (poll = fallback)
- [ ] money/safety path มี test (proration, GPS, auth, IDOR)
- [ ] tracking + notification ไม่ใช่ 0-test อีก
- [ ] force-revoke-all + refresh-reuse detection
- [ ] internal endpoint authenticated
- [ ] WebSocket events audited
- [ ] no SPOF บน DB (replica + pooler)
- [ ] Flutter screens thin + Riverpod + 0 orphan

---

[กลับ Overview](00-overview.md)
