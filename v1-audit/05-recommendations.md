# 05 · Recommendations for v2

ย้อนกลับ → [04 Tests](04-tests.md) · ถัดไป → [06 Migration Plan](06-migration-plan.md)

---

## 5.1 หลักการชี้นำ (Guiding Principles)

1. **อย่า big-bang rewrite** — ระบบยังไม่มี production users — เป็น dev/staging เท่านั้น. ใช้ strangler-fig **เป็นวินัย** (ป้องกัน big-bang risk + บังคับให้คิด rollback) **ไม่ใช่ข้อจำกัด user-availability**. แต่ละ phase ต้อง deploy + rollback ได้, แต่ dual-write / parallel-run / fallback **ทำเฉพาะที่ลด risk จริง** — ตัด overhead ที่ไม่จำเป็นได้ (เช่น Phase 1 ไม่ต้อง dual-write นาน, Phase 2 ไม่ต้องคง poll ตลอด rollout, Phase 3 ไม่ต้อง feature-flag traffic routing)
2. **Port ของที่ดีอยู่แล้ว** — tracking/notification/chat/shared lean และ correct ส่วนใหญ่ → port ตรง + เพิ่ม test
   > **หมายเหตุ:** "Port" ในที่นี้หมายถึง "reuse architecture + ขยายการรับประกัน" — ไม่ใช่ copy-paste. ทุก service ที่ port ต้องเพิ่ม test ครอบ critical path + ingress patterns ใหม่
3. **แตกของที่บวม** — booking + auth ต้องแตกก่อนเพิ่มฟีเจอร์ ไม่งั้น debt ทบ
4. **Push > Poll** — ย้าย booking status ไป WebSocket/event ตัด BUG race class ทั้งหมด
5. **Decouple via events** — แทน cross-schema write ด้วย event bus
6. **Test ก่อน refactor** — เขียน characterization test รอบ proration/auth/GPS ก่อนแตะ (ป้องกัน regression)

---

## 5.2 Per-Service: Redesign หรือ Port ตรง

| Service | คำตัดสิน | เหตุผล | งานหลัก |
|---|---|---|---|
| **tracking** | 🟢 **Port + Reinforced** | lean, 0 unwrap, boundary ชัด | + test suite, + WS message rate-limit ยืนยัน, + GPS audit |
| **notification** | 🟢 **Port + Reinforced** | lean | + authenticated REST ingress (`POST /notifications`), + service-JWT บน internal, + test, + index `(user_id, sent_at)` |
| **chat** | 🟡 **Port + Refactor (N+1)** | OK แต่ list_conversations N+1 | rewrite query (LATERAL JOIN), + participant auth test, + codec validation |
| **shared** | 🟢 **Port + Extend** | core แข็งแรง | + event-bus helper, + service-auth helper, + `token_revocation_version` check |
| **auth** | 🟠 **Module split** | god-service, 4 flow ปน | แยก: `auth-core` (JWT/session) · `identity` (profile) · `documents` (upload/watermark) · `otp` (SMS) — เริ่มเป็น module ใน crate เดียวก่อน แล้วค่อยแตก binary |
| **booking** | 🔴 **Service split** | god-service สุด 5 domain | แยก: `assignment-svc` (request+assignment+discovery) · `payment-svc` (payment+refund+receipt+proration) · `rating-svc` (reviews) · `call-svc` (C2 signaling) |
| **mediasoup** | 🟢 Port | Node SFU, isolated | + service-auth, + monitoring |
| **web admin** | 🟢 **Port + Light hardening** | debt ต่ำ | minor: CSRF token, commercial map tiles |
| **Flutter** | 🟠 **Refactor in-place** | debt ใน state layer | extract controller/widget, push-based, ลบ orphan — **ไม่ rewrite** |

---

## 5.3 Suggested Folder / Module Structure

### Backend — domain-layered crate (ตัวอย่าง booking → payment-svc)
```
services/payment/
├── src/
│   ├── main.rs            # wiring เท่านั้น (router, middleware, state)
│   ├── api/               # transport layer (thin handlers)
│   │   ├── mod.rs
│   │   ├── payments.rs    # handler → เรียก domain
│   │   └── refunds.rs
│   ├── domain/            # PURE logic, ไม่มี I/O — unit-testable 100%
│   │   ├── proration.rs   # compute_proration() ← ย้ายมาจาก booking/service.rs
│   │   ├── refund.rs      # state machine pending→processed/skipped
│   │   └── receipt.rs     # receipt_no derivation
│   ├── repo/              # SQLx queries (DB I/O แยกจาก domain)
│   │   └── payment_repo.rs
│   ├── events/            # emit/subscribe domain events
│   │   └── mod.rs
│   └── models.rs          # DTO
└── tests/
    └── integration.rs
```
**ประโยชน์:** `domain/proration.rs` test ได้โดยไม่แตะ DB — แก้ gap P0 ใน [04](04-tests.md) โดยตรง

### Flutter — feature-first + thin screens
```
lib/
├── core/
│   ├── network/           # ApiClient, sockets (AssignmentSocketService ← ย้ายจาก screen)
│   ├── auth/              # AuthRepository, token lifecycle
│   └── widgets/           # PGuardHeader ← extract จาก 17 หน้า (~1,190 LOC)
├── features/
│   ├── registration/      # orchestrator แยกจาก AuthProvider
│   ├── active_job/
│   │   ├── controller/    # CountdownController, ProgressReportManager ← extract math
│   │   ├── widgets/
│   │   └── active_job_screen.dart  # thin
│   ├── tracking/
│   └── booking/
└── shared/
```

---

## 5.4 Suggested Tech Upgrades

| ด้าน | ปัจจุบัน | เสนอ v2 | เหตุผล |
|---|---|---|---|
| **API versioning** | ไม่มี (ทุก endpoint = current) | **`/v1/` prefix ทุก service** + breaking change → `/v2/` per resource (ไม่ทั้ง service) | mobile/web จะแก้ทีละ endpoint ที่เปลี่ยน, ไม่ต้อง coordinate big-bang. gateway route version → service implementation. Deprecate /v1/ ตาม sunset date |
| **Inter-service comms** | direct DB write + unauthenticated HTTP | **Event bus (NATS / Redis Streams)** + authenticated REST | decouple, retry, replay, fan-out |
| **Cross-tx consistency** | ไม่มี | **Transactional outbox** | atomic business+event |
| **Flutter state** | Provider (ChangeNotifier), god-providers | **Riverpod** (หรือ BLoC) | testable, dependency injection, ลด coupling provider-to-provider |
| **Flutter booking status** | REST polling 3-5s | **WebSocket subscription** | ตัด BUG race class |
| **DB access** | SQLx runtime API (convention) | คงไว้ + **เพิ่ม compile-time `query!` ตรงที่ vanilla** | catch schema mismatch ตอน build |
| **DB scaling** | single Postgres, 6 pool | **pgbouncer** + read replica สำหรับ list/report | ลด SPOF, รับ load |
| **Caching** | Redis manual SET_EX | คงไว้ + cache invalidation ผ่าน event | consistency |
| **Observability** | tracing + audit | **OpenTelemetry** (trace ข้าม service) + correlation ID | debug distributed |
| **Secrets** | GitHub Actions secrets | **Vault / AWS Secrets Manager** + rotation | rotation policy |
| **Map tiles** | OSM (dev) | **Mapbox / MapTiler** | production ToS |
| **CI** | cargo test (live deps) | **split unit/integration** + flutter test + coverage gate | hermetic, เร็ว |
| **Push** | FCM | คงไว้ + retry queue ผ่าน event bus | reliability |

> **Versioning policy:** API gateway expose `/v{N}/{service}/...`. แต่ละ service version per-resource ใน OpenAPI spec. Breaking change ใน 1 endpoint = bump เฉพาะ endpoint นั้น (ไม่ใช่ทั้ง service). Sunset header (`Sunset: <date>`, `Deprecation: true`) ให้ client transition. Mobile app force-upgrade ถ้า endpoint version ที่ใช้ถูก sunset ไปแล้ว.

---

## 5.5 Missing Abstractions ที่ต้องสร้าง

1. **EventBus trait** (shared) — `publish(event)` / `subscribe(topic)` — แทน `spawn_notification`
2. **ServiceAuth** (shared) — issue/verify service-JWT สำหรับ internal calls
3. **NotificationDispatcher** (notification svc) — รับ event → สร้าง log + push (logic รวมศูนย์ที่เดียว)
4. **CountdownController + ProgressReportManager** (Flutter) — pure logic, testable
5. **AssignmentSocketService** (Flutter) — WS lifecycle ออกจาก screen
6. **PGuardHeader widget** (Flutter) — ลบ 1,190 LOC ซ้ำ
7. **Outbox relay** — poll outbox table → publish events

---

## 5.6 Migration Risk Matrix

| รายการ | ความเสี่ยง | impact ถ้าพลาด | mitigation |
|---|---|---|---|
| แตก booking → 4 service | 🔴 สูงสุด | payment/assignment พังพร้อมกัน | แตกเป็น module ใน crate เดิมก่อน (logical split) → แตก binary ทีหลัง; characterization test ครอบ proration ก่อน |
| ย้าย cross-schema write → event bus | 🔴 สูง | notification หาย / double | dual-write ช่วงเปลี่ยน (เขียนทั้งเก่า+ใหม่) + reconcile; outbox |
| Flutter Provider → Riverpod | 🟠 สูง | regression ทั้งแอป | migrate ทีละ feature, ไม่ทั้งหมดรอบเดียว |
| REST poll → WebSocket | 🟠 สูง | status ไม่ update | คง poll เป็น fallback ระหว่าง rollout |
| แตก auth → module | 🟠 กลาง | login พัง | auth integration test มีอยู่แล้ว (45 funcs) ช่วย guard |
| เพิ่ม token_revocation_version | 🟡 กลาง | revoke ผิดพลาด → logout หมด | rollout หลัง refresh chain, test ก่อน |
| pgbouncer + read replica | 🟡 กลาง | stale read | route เฉพาะ report/list ไป replica |
| ลบ orphan screens | 🟢 ต่ำ | — | grep ยืนยัน 0 reference ก่อนลบ |
| Map tile provider | 🟢 ต่ำ | — | config swap |
| add indexes | 🟢 ต่ำ | lock ตอนสร้าง | `CREATE INDEX CONCURRENTLY` |

---

## 5.7 Operational Maturity Gaps

> Audit นี้เน้น code/architecture — แต่ความพร้อม production ไม่ได้ขึ้นกับโค้ดอย่างเดียว. ช่องว่างด้าน operations ด้านล่างต้องปิดก่อนรับ production traffic จริง (ส่วนใหญ่ทำใน Phase 5 แต่ควรวาง policy ตั้งแต่ต้น)

| ด้าน | สถานะปัจจุบัน | gap | เสนอ v2 |
|---|---|---|---|
| Backup/restore | manual postgres dump (ตรวจ) | ไม่มี RPO/RTO defined, ไม่มี restore drill | RPO ≤ 1 ชม., RTO ≤ 4 ชม., monthly restore drill |
| Disaster recovery | single-region | ไม่มี | secondary region replica (Phase 5) |
| On-call runbook | ไม่มี | DB ล่ม / Redis ล่ม / nginx ล่ม = ad-hoc | runbook ต่อ component, escalation matrix |
| SLO definition | ไม่มี | ไม่รู้ว่า "ดี" คือเท่าไหร่ | p99 latency + availability per critical path, error budget |
| Monitoring/alerting | logging อย่างเดียว | ไม่มี alert routing | Prometheus + Alertmanager → Slack/PagerDuty |
| Secret rotation | ไม่มี policy | rotate manually เมื่อจำเป็น | quarterly rotation, Vault for prod |
| Cost monitoring | ไม่มี | infra cost ไม่ tracked | monthly cost report per service |

---

ถัดไป → [06 Migration Plan](06-migration-plan.md)
