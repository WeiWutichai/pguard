# PHASE spec — Mobile check-in wiring (ชิ้นปิดท้ายกลุ่ม A)

> **Slice:** ต่อ check-in flow ของ guard (สร้างเสร็จแล้วทั้ง UI/scheduling/capture)
> เข้า endpoint จริง `POST /v1/bookings/{id}/progress-reports` — แทนที่
> `PendingCheckInService` ที่โยน NOT_IMPLEMENTED
> **Worktree:** `feat/mobile-checkin-wiring` off `main` (`47c0975` ขึ้นไป)
> **แตะเฉพาะ `apps/mobile/`** + PROGRESS.md · **ห้ามแตะ `../guard-dispatch/`**
> **ใช้ terminal เดียว** — อย่ารัน spec นี้ซ้ำหลาย session (บทเรียน PR #28)

---

## ⚠️ กับดักอันดับหนึ่ง: field names ใน interface เดิมเป็นการ "เดาแบบ v1" — ผิดจาก contract จริง

`apps/mobile/lib/core/network/check_in_service.dart` (doc-comment หัวไฟล์) เขียนคาดไว้:
`hour_number, message, files` — **แต่ contract จริงที่ merge แล้ว**
(`contracts/openapi/booking.yaml:591 ProgressReportUploadForm`) คือ:

| part | จำเป็น | spec จริง |
|---|---|---|
| `hour_number` | ✅ | int32 ≥1 |
| `photo` | ✅ | **ตัวเดียว** (ไม่ใช่ `files`) — JPEG/PNG/WEBP ≤10MB, part ต้องประกาศ Content-Type ตรง MIME จริง (server ตรวจ magic bytes) |
| `lat` / `lng` | optional | double, ส่งเป็นคู่ |
| `accuracy` | optional | float เมตร (ค่าเพี้ยน server ทิ้งเป็น null เอง) |
| `note` | optional | **ไม่ใช่ `message`** — ≤2000 chars, ว่าง = ไม่ส่ง |

Response: `ApiResponseEnvelope.data = ProgressReport` (id, booking_id, guard_id,
hour_number, photo_key, photo_url presigned TTL 1h, lat/lng/accuracy/note?, created_at)

Errors ที่ app ต้อง handle แยก: **409** = ชั่วโมงนั้น check-in แล้ว (idempotent —
treat เป็น success-equivalent ใน UX, ดู scheduling state) หรือยังไม่ถึงเวลา hour N
(เปิดเมื่อผ่าน N−1 ชม.จาก work_started_at — message จาก server แยกแยะได้) ·
**413** = รูปใหญ่เกิน · **403/404** = ไม่ใช่ guard ของ booking นี้

## ของที่มีแล้ว (ห้าม reinvent)

- `CheckInService` interface + `PendingCheckInService` + provider override
  (`core/providers.dart`) — tests ใช้ fake ผ่าน provider อยู่แล้ว
- Capture flow: `core/media/photo_capture.dart` (`CapturedPhoto`) ·
  scheduling/missed logic ใน `active_job_controller.dart` ·
  UI `features/guard/widgets/check_in_sheet.dart` + `active_job_screen.dart`
- Multipart pattern อ้างได้: `ApiChatAttachmentService`
  (`core/media/chat_attachment_service.dart` — multipart + declared
  `DioMediaType` + 401-retry ผ่าน `FormData.clone()` ใน `api_client.dart`)
- GPS: `GpsSample` (lat, lng, accuracy, recordedAt)

## Scope of work

1. **`ApiCheckInService implements CheckInService`** — multipart POST ตาม
   ตารางข้างบนเป๊ะ (declared MIME จาก `CapturedPhoto`; ตามแพตเทิร์น attachment
   service) · แก้ doc-comment หัวไฟล์ที่ stale (backend มีแล้ว + field จริง)
2. **Interface เดิมคงรูป** (`submit({bookingId, hourNumber, photo, gps, note})`) —
   map `gps.accuracy` → part `accuracy`, `note` → `note`; ถ้า signature ต้องขยับ
   ให้ justify + แก้ fake/tests ตาม
3. Provider: สลับ default จาก `PendingCheckInService` → ตัวจริง
4. **Error UX ใน controller/sheet** (logic ใน controller ไม่ใช่ widget):
   409-duplicate = ถือว่าชั่วโมงนั้นเสร็จ (sync state, ไม่ error จอ) ·
   409-too-early = บอกเวลาที่เปิด · 413 = แจ้งรูปใหญ่เกิน ลองถ่ายใหม่ ·
   network fail = retry ได้ (server กัน orphan ฝั่งโน้นแล้ว — retry ปลอดภัย) ·
   ทุก message i18n TH/EN
5. หลัง submit สำเร็จ: อัปเดต check-in state ของ active job (ชั่วโมงไหนส่งแล้ว)
   — ใช้ ProgressReport ที่ server คืน หรือ refetch `GET /bookings/{id}/progress-reports`
   (เลือก+justify; ระวังอย่า poll)

### Out of scope
- จอดู progress-reports ฝั่ง customer (slice แยก ถ้าอยากมี)
- แก้ backend ใดๆ · video check-in

## Hard rules (ย้ำ)
- Riverpod codegen เท่านั้น · ไม่มี `Timer.periodic` · logic ใน controller ·
  ไม่เพิ่ม dependency ถ้าของเดิมพอ (dio multipart มีครบ)

## Definition of Done
1. `flutter analyze` clean · `flutter test` เขียวทั้ง suite (fake `CheckInService`
   เดิมต้องยังใช้ได้กับ tests scheduling เดิม)
2. Tests ใหม่: ApiCheckInService สร้าง FormData ถูก (field names + MIME ตรง
   contract — golden test ระดับ request) · 409 duplicate → state synced ·
   409 too-early → message ถูก · 413 → message ถูก · 401-retry ไม่พังกับ
   multipart (FormData.clone path) · submit สำเร็จ → ชั่วโมง mark แล้ว
3. i18n TH/EN parity ทุก string ใหม่
4. `PROGRESS.md`: tick กลุ่ม A ข้อสุดท้าย + log row + อัปเดต Phase 2 line
   ("เหลือ mobile check-in wiring" → done)
5. own PR off main — ไม่ merge เอง

## Review gate
2 agents (code + flutter/architecture; จุดเพ่ง: field names ตรง contract จริง ไม่ใช่
doc-comment เก่า · 409 สองความหมายแยกถูก · ไม่มี polling · fake compatibility)
→ fold blockers ก่อนปิด

## Smoke หลัง merge (wei ทำเอง — จดไว้ให้)
build app ชี้ staging → guard รับงาน → start → ถ่ายรูป check-in ชั่วโมง 1 →
ดู 200 + รูปขึ้น MinIO (`GET /bookings/{id}/progress-reports` เห็น photo_url) →
กดส่งซ้ำชั่วโมงเดิม → app ไม่ error (409 absorbed)
