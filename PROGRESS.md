# PROGRESS — pguard build tracker

> 👉 **เริ่มที่ `KICKOFF.md`** (entry point สำหรับ Claude Code) แล้วค่อยมาดูสถานะ task ที่นี่
>
> **กระดานเดียวที่ดูความคืบหน้า.** Claude Code ต้องอัปเดตไฟล์นี้ทุกครั้งที่จบ task (ดู Definition of Done ด้านล่าง).
>
> - **อยากรู้ว่าเหลืออะไร / ทำอะไรอยู่** → ดู *Phase board* + รายการ checkbox ข้างล่าง
> - **อยากรู้ว่า Claude Code เพิ่งทำอะไรเสร็จ** → ดู *Completed log* ท้ายไฟล์ (ใหม่สุดอยู่บนสุด)
>
> Legend: `[ ]` ยังไม่ทำ · `[~]` กำลังทำ · `[x]` เสร็จ + verify แล้ว
> Last updated: 2026-06-04

---

## Definition of Done — ติ๊ก `[x]` ได้ต่อเมื่อครบทั้ง 4 ข้อ

1. งานเสร็จตาม acceptance ของ task นั้น
2. **Verify แล้ว** — ตามชนิดงาน: `cargo test` + `cargo clippy -D warnings` (Rust) · `flutter test` + `flutter analyze` (mobile) · `pnpm build` (web) · อ่าน diff/รัน script (เอกสาร/UI)
3. ติ๊ก checkbox ในไฟล์นี้ **+ เพิ่ม 1 แถวใน Completed log** (วันที่ · task · ทำอะไร · ไฟล์ที่แตะ · verify ยังไง)
4. ถ้าเป็นงาน **UI** → เขียนบรรทัดบอก user ให้ reload Review Console เพื่อ re-check จอที่แก้

> ถ้า verify ไม่ผ่าน / ทำไม่จบ → ปล่อยเป็น `[~]` และจดบล็อกเกอร์ไว้ใต้ task นั้น ห้ามติ๊ก `[x]`

---

## Phase board (ภาพรวม)

- [x] Phase 1 — Audit (7 ไฟล์ใน `v1-audit/`)
- [x] Phase 1 revisions (9/9 applied)
- [ ] **Phase 0.5 — Baseline + PDPA + cost**  ⬅️ ทำอยู่ตอนนี้
- [ ] Phase 0 — Stabilize & safety net
- [~] Phase 1 — Decouple notifications (event bus + service-auth) — notification consumer + service-JWT **done** (KICKOFF §2.4); เหลือ booking-side emit + outbox cut-over
- [ ] Phase 2 — Push-based mobile (WS แทน polling)
- [ ] Phase 3 — Split booking (call → payment → rating → assignment)
- [ ] Phase 4 — Split auth + Flutter Riverpod migration
- [ ] Phase 5 — Scale & harden

---

## 🚀 Kickoff — v2 scaffold (KICKOFF.md §2)

โครงสร้าง v2 monorepo จริง (Rust workspace + apps + contracts + infra) — guardrails จาก audit/baseline

- [x] **§2.1 Scaffold monorepo + healthz** — Rust workspace (14 crates: 3 packages + 11 services), ทุก service มี `/healthz` · `apps/` (web-admin Next.js 16, mobile Flutter+Riverpod, design-tokens) · `services/mediasoup` (Node placeholder) · `tests/` `tooling/` `infra/` ครบตาม Service map
  - foundation crate `packages/shared-rust` (port v1 shared: error/models/config/db/auth/redis) **+ ใหม่ `service_jwt`** (แก้ v1 `/internal/push` ไม่มี auth) · `packages/shared-events` (EventEnvelope + topics) · `packages/observability` (`init_telemetry`, OTLP เป็น TODO)
- [x] **§2.2a First OpenAPI slice** — `contracts/openapi/notification.yaml` (3.1) + `contracts/asyncapi/events.yaml` (3.0, ตรงกับ `shared-events::topics`) + `contracts/db/migrations/notification/0001_init.sql` (per-service schema, ไม่มี cross-service FK)
- [~] **§2.2b Wire tooling/codegen** — `tooling/codegen/{README,generate.sh}` วาง scaffold แล้ว · **เหลือ implement generator จริง** (OpenAPI→Rust/Dart/TS)
- [x] **§2.3 infra/docker + dev-up.sh** — compose (postgres/nats-JS/redis/minio/otel/tempo/loki/prometheus/grafana, infra-only) + observability configs + `tooling/scripts/dev-up.sh` · **ยังไม่ `docker compose up`**
- [x] **§2.4 First vertical slice — notification** — `api/domain/repo/events` layering · port 8 v1 endpoints · NATS JetStream consumer (`pguard.events.*` → `notification_logs` + FCM, idempotent by `event_id` via `processed_events`) · **service-JWT บน `/internal/notifications/push`** (แก้ v1 ไม่มี auth) · FCM `Pusher` port (fail-fast config + NoopPusher) · +2 migration (processed_events + outbox)
  - **Reviewed (3 project agents):** `security-reviewer` ✅ Cleared (ปิด v1 risk #9 + Issue C1) · `architecture-guardian` ✅ Approve (ไม่มี hard-rule violation) · `code-reviewer` ⚠️→✅ หลังแก้ → **fix:** OpenAPI internal-push drift (notification เป็นเจ้าของ log), เพิ่ม OTel span (consumer+DB tx + correlation_id), rename `BOOKING_DECLINED` · deferred items บันทึกใน `.claude/agent-memory/security-reviewer/`
  - **E2E verified กับ infra จริง** (nats-server JetStream + Postgres + Redis): boot+`/healthz` ✅ · publish `booking.job_accepted` → consume → 1 log row ✅ · publish ซ้ำ event_id เดิม → `duplicate event; skipped` คงที่ 1 row (**idempotent บน wire จริง**) ✅ · publish id ใหม่ → 2 rows ✅ · OTel span (event_id+correlation_id) เห็นใน log · migration apply จริง + `process_event` real-DB integration test ผ่าน
- [ ] **§2.4-next** booking-side: emit `pguard.events.*` + transactional outbox → ตัด direct INSERT เดิม (จบ Phase 1) ⬅️ ถัดไป
- [ ] **§2.5** เดินตาม phase order ต่อ

**Verify (Definition of Done):** `cargo build --workspace` ✅ · `cargo clippy --workspace --all-targets -D warnings` ✅ · `cargo test --workspace` ✅ **54 passed/0 failed** (notification 15: domain mapping 8 + idempotency 2 + consumer-dedupe 2 + internal-push auth 3) · `cargo fmt --all --check` ✅ · YAML contracts parse ✅

---

## 🔴 Now — Phase 0.5 (Part B ของ `audit-revisions.md`)

รันใน Claude Code CLI ภายใน `guard-dispatch/` · brief: `audit-revisions.md` Part B

- [~] **B1** — `v1-audit/perf-baseline/` : 6 k6 scripts + `_common.js` + `README.md` + `results.md` เขียนครบ + validate parse แล้ว · **เหลือ user รัน k6 เติมตัวเลขจริงใน results.md** (sandbox เข้า localhost services ไม่ได้)
- [x] **B2** — `v1-audit/07-pdpa.md` §7.1–7.6 ครบ verify กับโค้ด v1 · แก้ 3 จุดที่ brief ผิด (audit_logs ชื่อจริง, location_history ยังไม่มี retention จริง, inventory ตก check-in photos/sessions IP/fcm tokens/call logs)
- [x] **B3** — `v1-audit/cost-baseline.md` : 12 container footprint + v2 delta (~+30–50%, ส่วนใหญ่ลง Phase 5) + เจอ finding "ไม่มี resource limit"
- [x] **B4** — อัปเดตตาราง "ไฟล์ที่สร้าง" ใน `v1-audit/00-overview.md` (07-pdpa, perf-baseline, cost-baseline)

**Exit:** ⏳ เกือบครบ — เหลือแค่ตัวเลข perf (B1) ที่ต้องรันจริง → จากนั้น gate ที่ user review ก่อนไป Phase 0
**Blocker B1:** ต้อง `docker compose up` v1 + seed data + รัน k6 บนเครื่อง user (ดู `perf-baseline/README.md`)

---

## 🟠 Next — Role mismatch fixes (รออนุมัติแนวทาง)

3 mismatch จาก `docs/reviews/frontend-backend-permission-mismatch.html` · แนะนำ: **B ก่อน แล้ว A ใน PR เดียวของ Phase 0**

- [ ] **#3** (MEDIUM) chat `actingRole` — มี backend gap จริง
  - `frontend/mobile/lib/screens/chat_list_screen.dart` — assert `actingRole` ใน constructor + `initState`
  - `services/chat/src/handlers.rs` — `list_conversations` reject `?role=` ที่ไม่ตรง JWT (admin ยกเว้น)
- [ ] **#1 #2** (LOW) + bonus
  - `services/booking/src/handlers.rs` — `available_guards()` : `if user.role != "customer" → Forbidden`
  - `services/booking/src/handlers.rs` — `create_payment()` : customer-only check
  - `frontend/mobile/lib/screens/guard/guard_dashboard_screen.dart` — `initState` defensive redirect
  - `frontend/mobile/lib/screens/live_map_screen.dart` — `initState` reject guards/unauthenticated
- [ ] regression tests + `cargo test` + `flutter test`

---

## 🟢 Later — Phase 0 (Stabilize & Safety Net)

หลัง Phase 0.5 ออก baseline · brief: `v1-audit/06-migration-plan.md` Phase 0

- [ ] Proration unit tests (`compute_proration`, `prorate_payment_in_tx`)
- [ ] `GpsUpdate::validate()` unit tests
- [ ] Cross-service jti revocation integration test
- [ ] nginx `s3_limit 10r/s` บน `/minio-files/`
- [ ] nginx `admin_limit 5r/s` บน `/booking/admin/*`
- [ ] ยืนยัน WS 1/sec GPS drop ทำงาน (`services/tracking/src/handlers.rs:54-55`)
- [ ] แยก CI เป็น unit + integration + `flutter test` + `docker-compose.test.yml`
- [ ] ลบ 3 orphan Flutter screens (`set_password`, `registration_role`, `customer_login` ~600 LOC)
- [ ] รวม 2 ไฟล์ `guard_registration_screen`
- [ ] เพิ่ม index `notification_logs (user_id, sent_at)` (ใช้ `CREATE INDEX CONCURRENTLY`)

**Exit:** money/safety path มี test · CI เขียว 2 jobs · orphan ลบหมด → จากนั้น rename `guard-dispatch/` → `pguard/`

---

## 🎨 UI review fixes (จาก Review Console)

> เติมรายการที่นี่เมื่อ user export `pguard-ui-review.md` (จอที่ติ๊ก ✗/⚠) แล้วส่งให้ Claude Code แก้
> Claude Code: แก้ไฟล์ HTML ใน `redesign-pguard/project/pguard/` → ติ๊กที่นี่ → log → บอก user reload Console

- _(ยังไม่มี — รอ export รอบแรก)_

---

## ✅ Completed log (ใหม่สุดอยู่บนสุด)

| วันที่ | Task | ทำอะไร | ไฟล์ที่แตะ | verify |
|---|---|---|---|---|
| 2026-06-04 | §2.4 E2E proof (NATS) | พิสูจน์ event bus end-to-end กับ infra จริง: nats-server JetStream (brew, เลี่ยง Docker Hub throttle) + Postgres + Redis · apply migration จริง · รัน consumer · publish job_accepted → consume → 1 log; publish ซ้ำ → dedupe (คง 1); id ใหม่ → 2 · DATABASE_URL-gated real-DB idempotency test ผ่าน · เก็บ publisher example | (รันอย่างเดียว ไม่แก้ไฟล์ app) · ad-hoc containers/procs ถูกลบหมดแล้ว | logs: `handle_event{event_id,correlation_id}` + `duplicate event; skipped` · DB row count 1→1→2 |
| 2026-06-04 | §2.4 review + fixes | รัน review agent ตาม convention (.claude/agents): security-reviewer ✅ · architecture-guardian ✅ · code-reviewer ⚠️ → แก้ตาม findings: OpenAPI internal-push drift (v2 notification เป็นเจ้าของ log row, ไม่ใช่ caller), เพิ่ม OTel span บน consumer (`handle_event` + correlation_id) + DB tx (`process_event`), rename `BOOKING_JOB_DECLINED`→`BOOKING_DECLINED` · บันทึก deferred security items | `contracts/openapi/notification.yaml` · `services/notification/src/events/mod.rs` · `…/repo/mod.rs` · `…/domain/mapping.rs` · `packages/shared-events/src/lib.rs` · `.claude/agent-memory/security-reviewer/notification-deferred.md` | `clippy -D warnings` ✅ · `test` ✅ 15+4/0 · `fmt` ✅ · openapi parse ✅ |
| 2026-06-04 | §2.4 notification slice | สร้าง notification service จริง: `api/domain/repo/events` layering · port 8 endpoints v1 · NATS JetStream consumer (map `pguard.events.*`→log+FCM, idempotent ด้วย `processed_events`/event_id) · **service-JWT บน `/internal/notifications/push`** (`ServiceCaller`) · FCM `Pusher` port (FcmPusher fail-fast + NoopPusher) · domain pure (ไม่มี DB/HTTP) | `services/notification/src/{main,models,state,fcm}.rs` + `{api,domain,repo,events}/` · `services/notification/Cargo.toml` · root `Cargo.toml` (sqlx json, async-trait, futures) · `contracts/db/migrations/notification/0002_event_consumer.sql` · `contracts/asyncapi/events.yaml` · `contracts/openapi/notification.yaml` | `cargo build -p pguard-notification` ✅ · `clippy -p … -D warnings` ✅ · `test` ✅ 15/0 · workspace `clippy`+`test 54/0`+`fmt` ✅ |
| 2026-06-04 | §2.4 spec | เขียน work-spec notification vertical slice (พอร์ต v1 + event bus/service-JWT/outbox/idempotency + DoD) ให้ Claude Code | `docs/PHASE1-notification-spec.md` · `PROGRESS.md` | อ่าน v1 notification routes/handlers/fcm จริงก่อนเขียน |
| 2026-06-04 | Kickoff §2.1 scaffold | Rust workspace 14 crates (3 packages + 11 services) ทุกตัวมี `/healthz` · port v1 `shared` → `packages/shared-rust` + ใหม่ `service_jwt` (auth ให้ internal calls) · `shared-events` (envelope+topics) · `observability` (init_telemetry) | `Cargo.toml` · `packages/**` · `services/**` (Cargo.toml+main.rs) · `services/mediasoup/{package.json,README}` | `cargo build` ✅ · `clippy -D warnings` ✅ · `test` ✅ 39/0 · `fmt --check` ✅ |
| 2026-06-04 | Kickoff §2.2a contracts | first OpenAPI slice (notification) + asyncapi events (ตรงกับ shared-events) + notification 0001 migration (per-service schema, no cross-svc FK) + contracts/README | `contracts/openapi/notification.yaml` · `contracts/asyncapi/events.yaml` · `contracts/db/migrations/notification/0001_init.sql` · `contracts/README.md` | `yaml.safe_load` parse ✅ ทุกไฟล์ |
| 2026-06-04 | Kickoff peripherals (workflow) | 4 agents ขนาน scaffold: web-admin (Next 16 App Router strict TS), mobile (Flutter+Riverpod), design-tokens, infra (compose infra-only + otel/tempo/loki/prometheus/grafana), tooling (dev-up/down, codegen), tests (e2e/contract/load) | `apps/web-admin/**` · `apps/mobile/**` · `apps/design-tokens/**` · `infra/**` · `tooling/**` · `tests/**` | `docker compose config` ✅ + PyYAML ทุก yaml ✅ · ไม่รัน installer/build |
| 2026-06-04 | Kickoff doc | รวมงาน + ขั้นตอนเริ่ม v2 เป็น `KICKOFF.md` (entry สำหรับ Claude Code) + pointer ใน PROGRESS | `KICKOFF.md` · `PROGRESS.md` | อ่าน diff |
| 2026-06-04 | แยก v1/v2 | ตัดสินใจแยกโปรเจกต์: guard-dispatch = reference อ่านอย่างเดียว, pguard = v2. ลบโค้ด v1 ที่เคย copy เข้ามาออกหมด + เพิ่ม section "Relationship to v1" ใน CLAUDE.md (ห้าม copy/แก้ v1) | `CLAUDE.md` · ลบ services/frontend/database/nginx/v2-audit/ ฯลฯ ออกจาก pguard | pguard เหลือ 13 items/2.0M · ไม่มี v1 leftover · guard-dispatch intact |
| 2026-06-04 | B1 seed | เขียน `seed.sql` (1 customer+1 guard creds Argon2 จริง, 200 online guards, 100 conversations+requests) + แก้ booking-create/payment-create ให้ field ตรง DTO จริง | `perf-baseline/scripts/seed.sql` · `booking-create.js` · `payment-create.js` · `README.md` | `node --check` 2 scripts ผ่าน · `pglast` parse seed.sql ผ่าน (15 stmts) · Argon2 verify ผ่าน |
| 2026-06-04 | Phase 0.5 B4 | อัปเดตตารางไฟล์ overview + ติ๊ก PROGRESS | `v1-audit/00-overview.md` · `PROGRESS.md` | อ่าน diff |
| 2026-06-04 | Phase 0.5 B2 (PDPA) | เขียน 07-pdpa.md §7.1–7.6 verify กับ schema/route จริง · แก้ 3 จุด brief ผิด | `v1-audit/07-pdpa.md` | grep migrations + routes ยืนยัน inventory/retention/`/me` methods |
| 2026-06-04 | Phase 0.5 B3 (cost) | footprint 12 container + v2 delta per phase | `v1-audit/cost-baseline.md` | อ่าน docker-compose.yml (services/images/no-limits) |
| 2026-06-04 | Phase 0.5 B1 (perf) | 6 k6 scripts + _common + README + results template (ตัวเลขรอ user รัน) | `v1-audit/perf-baseline/**` | `node --check` ทั้ง 7 ไฟล์ผ่าน · routes ยืนยันกับ v1 |
| 2026-06-04 | Review Console | สร้าง UI review console (39 จอ, light/dark, TH/EN, เทียบ 2 จอ, checklist+export) + ผูก role-access-matrix / mismatch / Coverage Matrix เป็นกลุ่ม Reference | `redesign-pguard/project/pguard/Review Console.html` | `node --check` JS ผ่าน · catalog = 39 จอ + 3 ref · path อ้างอิง resolve ครบ |
| 2026-06-04 | Self-contained | รวม pguard ให้ครบในโฟลเดอร์เดียว (79 ไฟล์) + `SESSION_HANDOFF.md` | ทั้งโปรเจกต์ | sanity check §8 ผ่าน |
