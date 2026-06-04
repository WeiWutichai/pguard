# P-Guard v2 — Architecture Audit

> **วันที่:** 2026-06-03 · **Scope:** guard-dispatch monorepo (Rust backend + Flutter mobile + Next.js web admin + infra)
> **วัตถุประสงค์:** ใช้เป็นพื้นฐาน (baseline) สำหรับการออกแบบ p-guard v2 — ระบุ tech debt, coupling, security gap, test gap และเส้นทาง migration

---

## วิธีอ่านรายงานนี้

| ไฟล์ | เนื้อหา |
|---|---|
| [01-current-state.md](01-current-state.md) | Service boundaries, cross-service coupling, data ownership, tech debt hotspots, frontend duplication, legacy code |
| [02-issues.md](02-issues.md) | Coupling problems, single points of failure, missing abstractions, state-management leak, N+1 / index gaps |
| [03-security.md](03-security.md) | JWT/session gaps, rate limiting completeness, audit log gaps, top security risks ranked |
| [04-tests.md](04-tests.md) | Test inventory per service, critical-path coverage (auth/payment/GPS), Flutter gaps, coverage matrix |
| [05-recommendations.md](05-recommendations.md) | Per-service redesign vs port, folder/module structure, tech upgrades, migration risk matrix |
| [06-migration-plan.md](06-migration-plan.md) | Phased rollout (6 phases), sequencing, rollback strategy |
| [07-pdpa.md](07-pdpa.md) | **(Phase 0.5)** PDPA compliance audit — data inventory, §19–34 rights matrix, retention gaps, cross-border, top 9 risks |
| [perf-baseline/README.md](perf-baseline/README.md) + [results.md](perf-baseline/results.md) | **(Phase 0.5)** k6 perf-baseline methodology + 6 scripts + results table (the "must not regress +20%" gate) |
| [cost-baseline.md](cost-baseline.md) | **(Phase 0.5)** v1 infra footprint + v2 cost delta (~+30–50%, mostly Phase 5) |

---

## สรุปผู้บริหาร (Executive Summary)

P-Guard เป็น MVP ที่ **โตเต็มฟีเจอร์แต่มี debt สะสม** จากการแก้บั๊กแบบ rapid-fire (BUG-001 … BUG-057). โครงสร้าง microservices ตั้งต้นมาดี (network isolation, JWT hardening, magic-byte validation, audit middleware ครบ 5 services) แต่มี **ปัญหาเชิงโครงสร้าง 5 ข้อหลัก** ที่ควรแก้ก่อนหรือระหว่างทำ v2:

1. **God-services** — `booking` (9,394 LOC) และ `auth` (6,770 LOC) แต่ละตัวรวม 4-5 domain ไว้ใน `service.rs` เดียว (booking/service.rs ~5,400 LOC). แก้ยาก ทดสอบยาก
2. **Cross-schema write coupling** — `booking` เขียนตรงเข้า `notification.notification_logs` และ `chat.messages` (ไม่ได้ผ่าน service เจ้าของ schema). ไม่มี event bus
3. **REST polling แทน push** — Flutter 5 หน้าใช้ `Timer.periodic` poll สถานะ booking ทุก 3-5 วินาที (13 timers ในกรณีแย่สุด). มี WebSocket เฉพาะ chat + GPS
4. **Test gap วิกฤต** — `tracking` และ `notification` มี **0 test**; proration math (เงิน) และ `GpsUpdate::validate()` ไม่มี unit test เลย
5. **Security gap เทียบ best-practice 2026** — ไม่มี force-revoke-all-tokens, ไม่มี refresh-reuse detection, internal endpoint ไม่มี auth, WebSocket ไม่ถูก audit

> **ข้อสรุปเชิงกลยุทธ์:** ส่วนใหญ่ของ backend **port ตรงได้** (lean services: tracking, notification, chat) แต่ `booking` และ `auth` ควร **แตกเป็น sub-services / modules** ก่อน. Flutter ควร refactor state layer (extract business logic ออกจาก screens) มากกว่า rewrite ทั้งหมด. ไม่แนะนำ big-bang rewrite — ใช้ strangler-fig แบบเป็นเฟส (ดู [06](06-migration-plan.md)).

---

## ตัวเลขสำคัญ (Metrics at a glance)

| ด้าน | ตัวเลข |
|---|---|
| Rust services | 6 (shared, auth, booking, tracking, notification, chat) + mediasoup (Node) |
| Backend LOC | auth 9,549 · booking 9,394 · chat 2,428 · shared 2,046 · notification 1,098 · tracking 1,003 |
| DB migrations | 45 |
| Flutter LOC / screens | ~46,500 / 55 screens |
| BUG-XXX comments | 58 (mobile-heavy: customer_tracking 8, guard_job_detail 8) |
| `unwrap()` matches (prod paths) | ~92 grep matches — แต่ส่วนใหญ่ startup/cookie-parse/test (request path เสี่ยงต่ำ) |
| Cross-schema direct writes | booking → notification (10 sites), booking → chat (3 sites) |
| Rust integration tests | 1 ไฟล์ (auth เท่านั้น) + inline unit ~257 funcs |
| Services with 0 tests | 2 (tracking, notification) |
| Flutter tests | 4 ไฟล์ (PIN, registration form, baht text, widget placeholder) |
| Orphaned Flutter screens | 3 (set_password, registration_role, customer_login) ~600 LOC |
| nginx rate-limit zones | 5 (auth 5r/s · api 30r/s · ws 5r/s · otp 3r/m · swagger 10r/s) |

---

## ระดับความเสี่ยง migration (สรุป)

| Service / Layer | กลยุทธ์ v2 | ความเสี่ยง |
|---|---|---|
| (Phase 0.5) Baseline + PDPA | Read-only audit (perf + PDPA + cost) | 🟢 ต่ำ |
| tracking | Port ตรง + เพิ่ม test | 🟢 ต่ำ |
| notification | Port + เพิ่ม REST ingress + test | 🟢 ต่ำ |
| chat | Port + แก้ N+1 list_conversations | 🟡 กลาง |
| shared | Port + เพิ่ม event/service-auth helpers | 🟢 ต่ำ |
| auth | แตก 3-4 module (auth / profile / document / otp) | 🟠 สูง |
| booking | แตก 3-4 service (assignment / payment / rating / call) | 🔴 สูงสุด |
| Flutter | Refactor state + extract widgets (ไม่ rewrite) | 🟠 สูง |
| web admin | Port ตรง (debt ต่ำ) | 🟢 ต่ำ |

รายละเอียดเต็มอยู่ใน [05-recommendations.md](05-recommendations.md) และ [06-migration-plan.md](06-migration-plan.md).

> **Operational maturity:** นอกจาก code/architecture แล้ว ยังมีช่องว่างด้าน operations (backup/RPO-RTO, DR, on-call runbook, SLO, monitoring/alerting, secret rotation, cost) — ดู [§5.7 Operational Maturity Gaps](05-recommendations.md#57-operational-maturity-gaps)
