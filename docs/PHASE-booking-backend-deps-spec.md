# PHASE spec — Booking backend deps (progress-report + open-job discovery)

> **Slice:** ปิด 2 backend gap ที่ mobile guard-side รออยู่:
> (1) **progress-report endpoint** — hourly check-in photo+GPS (mobile สร้าง UI/flow ครบแล้ว
> แต่ endpoint ไม่มีใน v2) (2) **open-job discovery** — guard เห็น booking ที่ `requested`
> และยังไม่มี guard รับ
> **Worktree:** `feat/booking-backend-deps` off `main` (`d6cd046` ขึ้นไป)
> **ห้ามแตะ `../guard-dispatch/`** (read-only) · **ห้ามแตะ `services/api-gateway/`**
> (มี slice ขนานกำลังแก้อยู่ — กันชน)

---

## Gap evidence (อ่านก่อน)

- Mobile check-in flow เสร็จแล้ว: `apps/mobile/lib/core/network/check_in_service.dart`
  (`PendingCheckInService` โยน NOT_IMPLEMENTED) + `lib/features/guard/widgets/check_in_sheet.dart`
  — คาดหวัง `POST /v1/bookings/{id}/progress-reports` (photo + GPS + hour_number)
- Guard job discovery: `apps/mobile/lib/core/controllers/guard_jobs_controller.dart:12-16`
  comment ระบุ gap ตรงๆ — `GET /v1/bookings` คืนเฉพาะงานของ caller
  (`WHERE customer_id=$1 OR guard_id=$1`) ทำให้ guard ไม่มีทางเห็นงาน `requested` ที่
  `guard_id IS NULL`
- Photo storage pattern พร้อม port: `services/chat/src/s3.rs` (~199 บรรทัด, presigned
  SigV4 ไม่พึ่ง aws-sdk; internal upload + public download, ไม่ leak credential)

## Scope of work

### A. Contract ก่อน (OpenAPI = source of truth)
`contracts/openapi/booking.yaml` เพิ่ม:
1. `POST /bookings/{id}/progress-reports` — bearerAuth, guard-only (ต้องเป็น guard
   ที่ assigned กับ booking นั้น), body: photo (เลือกวิธี: presigned-upload 2 ขั้น
   ตามแพตเทิร์น chat **หรือ** multipart ตรง — justify ใน PR; แนะนำ presigned ให้
   binary อยู่ S3/MinIO ตามกติกา "binary blobs stay in S3"), `lat`/`lng`,
   `hour_number`, `note?`
2. `GET /bookings/{id}/progress-reports` — customer (เจ้าของ booking) + assigned guard
   อ่านได้ (IDOR-gated ทั้งสองทาง)
3. `GET /bookings/open` (หรือ query param `scope=open` บน `GET /bookings` — เลือก+justify;
   ระวังอย่าให้ collision กับ `/bookings/{id}`) — guard-only, คืน booking
   `status=requested AND guard_id IS NULL` ใกล้พิกัด guard (รับ `lat`/`lng`/`radius_km`
   optional; ไม่มีพิกัด = เรียงใหม่สุดก่อน, paginated)

### B. Booking service (`services/booking/`) — ตาม layering เดิม
1. Migration `contracts/db/migrations/booking/0003-progress-reports.sql` —
   ตาราง `booking.progress_reports` (id, booking_id FK ภายใน schema ตัวเอง, guard_id,
   hour_number, photo_key (S3 key ไม่ใช่ blob), lat, lng, note, created_at) + index
   (booking_id, hour_number) · `CREATE INDEX CONCURRENTLY` ถ้า production-relevant
2. `domain/` — กติกา pure: validate hour_number ตามช่วงเวลางาน (เทียบ booking
   start/duration จาก state machine เดิม) · งานต้อง `in_progress` เท่านั้นถึง check-in ได้
   · ซ้ำ hour เดิม = 409 (idempotent ฝั่ง guard กด retry)
3. `repo/` — SQLx (compile-time `query!` ถ้า vanilla) · open-job query แยกจาก list เดิม
   อย่าแก้ semantics `GET /bookings` ที่ client เดิมใช้
4. S3 presign — port แพตเทิร์นจาก `services/chat/src/s3.rs` มาไว้ใน booking
   (duplicate ได้ ไม่ต้อง extract เป็น shared crate ใน slice นี้ — จดเป็น follow-up)
5. `events/` — outbox: `pguard.events.booking.progress_reported` (envelope เดิม:
   event_id, event_type, occurred_at, correlation_id, payload) — notification service
   จะใช้แจ้ง customer ภายหลัง · เพิ่ม topic ใน `contracts/asyncapi/events.yaml`
6. **อย่า**แตะ assignment state machine เดิมเกินจำเป็น (tests เดิมต้องผ่านไม่แก้ expectation)

### C. ไม่อยู่ใน scope
- Mobile wiring (`PendingCheckInService` → ของจริง) — slice mobile แยกหลัง endpoint merge
- Gateway routing — `/bookings/*` route ผ่าน gateway อยู่แล้ว (prefix `/bookings` →
  Booking) จึง**ไม่ต้องแก้ gateway**; แต่ถ้าเลือก `GET /bookings/open` ให้เช็คว่า
  longest-prefix เดิมครอบ (ครอบอยู่แล้ว — แค่ confirm ใน test ฝั่ง booking)
- Notification consumer ของ event ใหม่

## Hard rules (ย้ำจาก CLAUDE.md)
- Axum 0.8 `/{id}` · ไม่มี `.unwrap()`/`.expect()` ใน request path · domain ห้าม import DB/HTTP
- Cross-service state change = event เท่านั้น · binary ไป S3 เก็บแค่ key
- `cargo fmt` + `clippy --workspace --all-targets -D warnings` clean

## Definition of Done
1. Unit tests `domain/`: hour-number validation · state-gate (`in_progress` only) ·
   duplicate-hour 409 · open-job filter (requested + unassigned เท่านั้น, ไม่รั่วงานคนอื่น)
2. Integration tests (gated DB ตามแพตเทิร์นเดิม): IDOR ทั้ง 3 endpoint
   (guard แปลกหน้า/customer คนอื่น = 403-404) · outbox row ถูกเขียนใน tx เดียวกับ insert
3. `cargo test --workspace` เขียว · fmt/clippy clean · migration apply ผ่าน `migrate.sh`
   บน Postgres สด (20→21 ok + idempotent re-run)
4. OpenAPI valid + อัปเดต `contracts/asyncapi/events.yaml`
5. `PROGRESS.md` tick + Completed-log row
6. own PR off main — ไม่ merge เอง

## Review gate
2 agents ขั้นต่ำ (code + architecture; จุดเพ่ง: IDOR · outbox atomicity · ไม่แตะ
semantics `GET /bookings` เดิม · S3 key ไม่ leak credential) → fold blockers ก่อนปิด
