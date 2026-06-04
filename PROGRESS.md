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
- [x] Phase 1 — Decouple notifications (event bus + service-auth) — notification consumer **+ booking emit via transactional outbox** done; ไม่มี cross-schema write (v2 ไม่เคยมี)
- [ ] Phase 2 — Push-based mobile (WS แทน polling)
- [~] Phase 3 — Split booking (call → payment → rating → assignment) — **payment** แยกออกมาแล้ว (proration + idempotent charge + outbox, อ่าน authoritative ผ่าน booking `/internal`); เหลือ call / rating / assignment
- [~] Phase 4 — Split auth + Flutter Riverpod migration — backend split **เสร็จ**: **identity** (login/refresh/revoke-all+trv) **+ otp** (INET SMS) **+ profile** (guard/customer + approval + bank masking); เหลือ Flutter Riverpod migration
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
- [x] **§2.4-next booking emit + outbox (จบ Phase 1)** — `booking` service: state machine (pure) + 8 endpoints + **transactional outbox** (status change + event row ใน tx เดียว) + relay → NATS · emit `pguard.events.booking.*` ให้ notification consume · IDOR ownership check (assigned-guard only) · build/clippy/test ✅ + outbox & IDOR real-DB test ผ่าน
- [x] **§2.4b identity/auth foundation (Phase 4 เริ่ม)** — `identity` service: login (Argon2 + anti-enumeration) · refresh rotation + **reuse detection** (RFC 6749 §6) · logout · `/auth/me` · **`/internal/users/{id}/revoke-all`** (service-JWT) + `user.compromised` consumer · **force-revoke-all จริง**: `trv` claim ใน `shared::auth` + AuthUser ปฏิเสธ token เก่า (Redis `user_trv:{id}`) → ปิด v1 risk #1
  - **2 slices ทำขนานกัน** (Workflow, worktree แยก) → merge → **review 3 agents**: security ✅ Cleared (ปิด risk #1 + IDOR) · architecture ✅ Approve · code-reviewer block (trv) → **แก้แล้ว → cleared** · เพิ่ม regression test (IDOR 403, trv stale) ผ่านกับ infra จริง
- [x] **§2.4c otp service (INET SMS)** — port v1: **INET CSGAPI** SMS (Cheese Digital Network, TIS-620/UCS-2) เป็น `SmsSender` port (InetSender + NoopSender ตาม `SMS_DISABLED`) · captcha → request → verify · config ทั้งหมดจาก `.env` (`INET_SMS_*`/`OTP_*`/`DAILY_OTP_LIMIT`, `.env.example` placeholder ไม่มี secret v1) · OTP **hash SHA-256** ใน Postgres + **constant-time compare** (`subtle`) · Redis cooldown/daily/tiered-lockout/captcha · single-use phone-verify JWT
  - **Review 3 agents**: security ⚠️→✅ (แก้ repo span เลิก log เบอร์โทร) · architecture ✅ Approve · code-reviewer ⚠️→✅ (ลบ dead `http_client` field) · 42 tests ผ่าน + gated tests (otp_lifecycle, router) ผ่านกับ PG+Redis จริง
- [x] **§2.4d profile service (ปิด backend Phase 4)** — `profile` service (AuthUser-gated, Postgres-only): guard/customer profile CRUD + **approval workflow** (admin approve/reject, row-locked + pure transition gate) + **bank account masking last-4** (PDPA, แก้ bug multibyte ของ v1) · reuse `shared::models::ApprovalStatus` · admin เห็นเลขเต็ม, owner เห็น masked
  - **Review 3 agents: ✅✅✅ Approve ทั้งหมด ไม่มี blocker** · เพิ่ม (จาก review): DB CHECK `years_of_experience` + test "re-upsert ไม่ reset approval" · 26 tests + gated repo/router ผ่านกับ PG+Redis จริง
- [x] **§2.4e api-gateway (edge — ปลดล็อก end-to-end)** — reverse proxy `/v1/<resource>` (longest-prefix, strip /v1) + **block `/internal/`** + **JWT-at-edge** (jti + trv force-revoke + CSRF, public allowlist login/refresh/otp) + **per-IP Redis rate limit** (tiers จาก v1 nginx: auth 5/s · otp 10/min · api 30/s, fail-open) + inject trusted `X-User-*` (strip client ก่อน, กัน spoof) + reqwest forward (1 MiB cap→413, hop-by-hop strip, →502) · domain pure (routing/ratelimit/headers) · backends คง AuthUser เอง (defense-in-depth)
  - **Review 3 agents**: architecture ✅ Approve · code-reviewer ✅ Approve · security ⚠️→✅ — **harden `/internal` block** (เพิ่มดัก trailing `/internal` + reject `%2f/%5c` encoded separator เพื่อกัน bypass) + log เลิกใส่ query string · 54 tests ผ่าน
- [x] **§2.4f payment service (Phase 3 — money path)** — `payment` service (`api/domain/repo/events`): `compute_proration` **ported verbatim จาก v1** (refund-on-completion, clamp actual ∈ [0,booked], round_dp 2) · create (customer-only) + complete (admin-only) endpoints · **authoritative customer/guard/status อ่านผ่าน service-JWT** จาก booking `GET /internal/bookings/{id}` (ไม่ trust client) · **idempotent charge** (`INSERT … ON CONFLICT (booking_id) WHERE status='completed' DO NOTHING` → retry คืน row เดิม ไม่ double-charge) + **transactional outbox** (charge/refund + event ใน tx เดียว) · money เป็น `rust_decimal::Decimal` ทุก field (ไม่มี f64) · `NUMERIC(12,2)` + partial-unique `uq_payment_one_completed_per_booking` · เพิ่ม booking `GET /internal/bookings/{id}` (ServiceCaller-gated, narrow projection)
  - **Review 3 agents**: security ✅ · architecture ✅ · code-reviewer — **must-fix (unanimous):** `rust_decimal` serde `serde-float`→**`serde-str`** (money บน wire เป็น JSON string ตาม OpenAPI/AsyncAPI contract, ไม่ใช่ float) → **แก้แล้ว** + เพิ่ม guard: scale > 2dp reject (`TooManyDecimals` — กัน `NUMERIC(12,2)` ปัดเงียบ) · `is_finalizable_status` (proration เฉพาะ booking `completed`) · `EnvelopeOf_RefundRef` message ใน AsyncAPI · test `money_serializes_as_string_not_float`
  - **DB-gated verified กับ Postgres จริง** (5433, apply payment 0001): `charge_is_idempotent` (retry → payment เดิม ไม่มี row ที่สอง) ✅ · `proration_writes_refund_row_and_event` (refund row + 1 refund event ใน outbox) ✅
- [ ] **§2.5** เดินตาม phase order ต่อ (Flutter Riverpod · rating/calling/presence/chat · profile-documents S3 upload · payment: authoritative price column + booking.completed consumer + gateway `/payments` route)

**Verify (Definition of Done):** `cargo build --workspace` ✅ · `cargo clippy --workspace --all-targets -D warnings` ✅ · `cargo test --workspace` ✅ **254 passed/0 failed** (api-gateway 54 · otp 42 · shared 35 · payment 30 · profile 26 · identity 25 · booking 21 · notification 16 · shared-events 4 · observability 1) · `cargo fmt --all --check` ✅ · gated tests (booking outbox/IDOR · trv · otp lifecycle · profile upsert/approve · gateway pipeline · **payment idempotent-charge + proration-refund**) ผ่านกับ PG+Redis จริง

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
| 2026-06-05 | payment service (money path) | build (Workflow, worktree) **payment** slice (Phase 3): `compute_proration` ported verbatim จาก v1 (refund-on-completion, clamp [0,booked], round_dp 2) · create (customer) + complete (admin) · authoritative customer/guard/status อ่านผ่าน **service-JWT** จาก booking `GET /internal/bookings/{id}` (ไม่ trust client) · **idempotent charge** (`ON CONFLICT (booking_id) WHERE status='completed' DO NOTHING` → ไม่ double-charge) + transactional outbox · money `Decimal` ทุก field · เพิ่ม booking internal-read endpoint (ServiceCaller) · **review 3 agents** → must-fix: `rust_decimal` `serde-float`→**`serde-str`** (money บน wire = JSON string ตาม contract) + scale>2dp reject + `is_finalizable_status` guard + `EnvelopeOf_RefundRef` AsyncAPI msg | `services/payment/**` · `services/booking/src/{api,repo,state,main,models}` · `contracts/openapi/{payment,booking}.yaml` · `contracts/db/migrations/payment/0001_init.sql` · `contracts/asyncapi/events.yaml` · root `Cargo.toml` (rust_decimal serde-str) | clippy --all-targets -D warnings ✅ · `test --workspace` **254/0** (payment 30 · booking 21) · fmt ✅ · asyncapi parse ✅ · **DB-gated กับ PG จริง** (5433): `charge_is_idempotent` + `proration_writes_refund_row_and_event` ผ่าน |
| 2026-06-04 | api-gateway service | build (Workflow, worktree) edge reverse-proxy: `/v1` resource routing (longest-prefix, strip `/v1` ก่อน forward) + **block `/internal/`** (404 ตาม v1 nginx) + per-IP rate limit (Redis fixed-window, fail-OPEN, tiers Auth/Otp/Api จาก v1 zones, env-override) + **JWT-at-edge** (jti blocklist + per-user trv force-revoke-all + CSRF parity ตาม `shared::auth`) + inject trusted `X-User-*` (strip client-supplied ก่อน) + reqwest forward (1 MiB body cap→413, hop-by-hop strip, unreachable→502) · domain/ pure (routing/ratelimit/headers) · backends คง AuthUser เอง (defense-in-depth) | `services/api-gateway/Cargo.toml` · `services/api-gateway/src/{main,state,auth,ratelimit,proxy,handler}.rs` · `services/api-gateway/src/domain/{mod,routing,ratelimit,headers}.rs` | `cargo build -p pguard-api-gateway` ✅ · `clippy --all-targets -D warnings` ✅ · `test` 54 (pure route-table/rate-decision/header + proxy integration ephemeral-upstream 413/502/strip/inject + gated full-pipeline 401/inject/internal-404 + **harden encoded-sep/trailing-internal block** จาก security review) ผ่านกับ Redis จริง + hermetic-skip · `fmt --check` ✅ |
| 2026-06-04 | profile service | build (Workflow, worktree) guard/customer profile CRUD + approval workflow (admin, row-locked + pure transition) + bank masking last-4 (PDPA, แก้ multibyte bug v1) · AuthUser-gated, Postgres-only · review 3 agents **✅✅✅ ไม่มี blocker** → เพิ่ม DB CHECK years + invariant test (re-upsert ไม่ reset approval) | `services/profile/**` · `contracts/openapi/profile.yaml` · `contracts/db/migrations/profile/0001_init.sql` | clippy -D warnings ✅ · test 26 + gated (upsert/approve, router 401/403) ผ่านกับ PG+Redis จริง · fmt ✅ |
| 2026-06-04 | otp service (INET SMS) | build (Workflow, worktree) port v1 INET CSGAPI SMS + OTP captcha/request/verify · config จาก `.env` (INET_SMS_*/OTP_*) · SHA-256 hash + constant-time compare + Redis abuse-control + phone-verify JWT · review 3 agents → แก้: repo span เลิก log เบอร์, ลบ dead `http_client` field | `services/otp/**` · `contracts/openapi/otp.yaml` · `contracts/db/migrations/otp/0001_init.sql` · `services/otp/.env.example` · root `Cargo.toml` (rand/sha2/subtle) | clippy -D warnings ✅ · test 42 hermetic + gated (otp_lifecycle, router) ผ่านกับ PG+Redis จริง · fmt ✅ |
| 2026-06-04 | identity + booking review fixes | แก้ตาม 3 review agents: **trv force-revoke-all** (`shared::auth` JwtClaims.trv + AuthUser เช็ค Redis `user_trv` → ปิด v1 risk #1) · booking **IDOR** ownership check · DUMMY_HASH LazyLock จริง · logout redis log · hours cap · identity handler spans · +regression test (IDOR 403, trv stale) · re-review: security ✅ + code-reviewer block cleared | `packages/shared-rust/src/auth.rs` · `services/identity/src/{api,repo,state,events,models}` · `services/booking/src/{api,repo}/mod.rs` | clippy -D warnings ✅ · test 97 hermetic + gated (booking 18 IDOR/outbox, shared 35 trv) ผ่านกับ PG+Redis จริง · fmt ✅ |
| 2026-06-04 | identity + booking slices (ขนาน) | สร้าง 2 vertical slice ขนานกันด้วย Workflow (worktree แยก): **identity** (login/refresh-rotation+reuse/logout/me/revoke-all + user.compromised consumer) + **booking** (state machine + 8 endpoints + transactional outbox + relay → emit `pguard.events.booking.*`) · cherry-pick เข้า `feat/identity-booking` | `services/identity/**` · `services/booking/**` · `contracts/openapi/{identity,booking}.yaml` · `contracts/db/migrations/{identity,booking}/0001_init.sql` · root `Cargo.toml` (sqlx json) | cargo build/clippy -D warnings/test ✅ · integration verify รวม 97/0 |
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
