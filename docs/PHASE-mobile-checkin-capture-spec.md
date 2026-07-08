# PHASE spec — Mobile check-in capture (กล้องจริง + ตัด end-of-shift slot + เก็บกวาด 401)

> **Micro-slice (mobile):** ปลดล็อก smoke check-in จากเครื่องจริง — 3 เรื่องเล็กใน
> `apps/mobile/` เท่านั้น
> **Worktree:** `feat/mobile-checkin-capture` off `main` (`6301f3b` ขึ้นไป)
> **ใช้ terminal เดียว** · ห้ามแตะ services/* · มี slice backend ขนานแตะ
> `core/network/check_in_service.dart` — **ห้ามแตะไฟล์นั้น** (กันชน)

---

## 1. กล้องจริง (บล็อก smoke อยู่ตอนนี้)

`core/media/photo_capture.dart` — default คือ `UnavailablePhotoCaptureService`
(คืน null เสมอ → sheet ขึ้น "กล้องไม่พร้อมใช้งานในรุ่นนี้") ทั้งที่ `image_picker`
เป็น dep อยู่แล้ว (ใช้ใน registration + chat media picker)

- เพิ่ม impl จริง: `ImagePicker().pickImage(source: ImageSource.camera, ...)` →
  `CapturedPhoto(path, sizeBytes)` — ดู `chat_media_picker.dart` เป็น precedent
  (จำกัด resolution/quality ตามที่ picker ฝั่ง chat ทำ เพื่อคุมขนาดใต้ 10MB)
- cancel/permission denied → คืน null (พฤติกรรม UI เดิมรองรับแล้ว)
- สลับ provider default → ตัวจริง; fake ใน tests คงเดิม

## 2. ตัด end-of-shift slot (รูปปิดกะถูกทิ้งเงียบ)

`core/controllers/guard_clock.dart` — `CheckInSchedule.totalSlots = hours + 1`
(slot 0..hours) แต่ server รับ `hour_number` 1..hours เท่านั้น → slot สุดท้าย
ถูก clamp ชน hour เดิม โดน 409 absorb = **รูปปิดกะไม่มี record ฝั่ง server**
(documented trade-off จาก PR #29)

- แก้ schedule เหลือ `hours` slots (slot 0..hours-1 → hour 1..hours, map 1:1
  ไม่ต้องชน) — UI label "เช็คอินเริ่มงาน / ชั่วโมงที่ N" ปรับตาม
- คง clamp ใน `active_job_controller.dart` ไว้เป็น defensive (ไม่ควร trigger แล้ว —
  เพิ่ม comment)
- แก้ tests schedule/controller ที่อิง totalSlots เดิม (อนุญาตแก้ expectation
  เฉพาะที่สะท้อน slot model ใหม่ — ระบุใน PR ว่าแก้ตัวไหนเพราะอะไร)

## 3. เก็บกวาด dead 401-retry path

`core/network/api_client.dart` — `validateStatus: <500` ทำให้ 401 ไม่เคยเป็น
`DioException` → `_onError` (ที่ถือ `FormData.clone()`) เป็น dead code;
proactive refresh ใน `_onRequest` คือกลไกจริง (ยืนยันจาก audit PR #29)

เลือก 1 ทาง + justify:
- (ก) **ทำให้ live**: เช็ค 401 ใน `_send` → refresh → retry หนเดียว (FormData
  ต้อง clone ก่อน retry) — แข็งแรงขึ้นกรณี token โดน revoke กลางคัน
- (ข) **ลบทิ้ง**: ตัด `_onError` clone path + comment ว่า proactive refresh
  คือกลไกเดียว (เรียบง่าย แต่ revoke กลางคัน = user เด้ง login)

ห้ามแตะพฤติกรรม proactive refresh เดิม (มี test คุมอยู่)

## Hard rules (ย้ำ)
Riverpod codegen · ไม่มี Timer.periodic · logic ใน controller · ไม่เพิ่ม dependency
(image_picker มีแล้ว) · i18n TH/EN ทุก string ใหม่

## Definition of Done
1. `flutter analyze` clean · `flutter test` เขียวทั้ง suite
2. Tests ใหม่/แก้: capture จริง mock ที่ seam (picker คืน file → CapturedPhoto;
   คืน null → UI เดิม) · schedule N hours = N slots + label · slot สุดท้าย map
   hour=hours ไม่ clamp · ทางที่เลือกในข้อ 3 มี test คุม
3. `PROGRESS.md` log row (+ note ว่า trade-off end-of-shift จาก PR #29 ปิดแล้ว)
4. own PR off main — ไม่ merge เอง

## Review gate
2 agents (code + flutter) — จุดเพ่ง: ไม่แตะ `check_in_service.dart` · slot
re-model ไม่ทำ scheduling/missed logic เดิมเพี้ยน · permission-denied path
