# PHASE spec — 409 sub-code สำหรับ duplicate check-in (เลิก string-match)

> **Micro-slice (backend + client จุดเดียว):** ตอนนี้ mobile แยก 409-duplicate
> ("ชั่วโมงนี้ส่งแล้ว" → absorb เป็น success) จาก 409-too-early ด้วย **substring
> ภาษาอังกฤษ** (`"already exists"`) — ถูกวันนี้ แต่เปราะ: แก้ wording ฝั่ง server
> เมื่อไหร่ logic ฝั่ง app พังเงียบ
> **Worktree:** `feat/checkin-409-subcode` off `main` (`6301f3b` ขึ้นไป)
> **ใช้ terminal เดียว** · มี slice mobile ขนาน — ฝั่ง mobile **แตะได้เฉพาะ
> `core/network/check_in_service.dart` + test ของมัน** (ห้ามแตะ photo_capture /
> guard_clock / api_client / providers)

---

## ที่มา (จาก audit PR #29)

- ทั้งสอง 409 ใช้ `AppError::Conflict` → code `"CONFLICT"` ตัวเดียว
  (`packages/shared-rust/src/error.rs:58`) — ไม่มี machine-readable discriminator
- จุด emit duplicate: `services/booking/src/api/mod.rs:382` (pre-flight) +
  `repo/mod.rs:454` (unique-index 23505) — ทั้งคู่ "A check-in for hour {N} already exists"
- ฝั่ง client: `_isDuplicateHour` ใน `apps/mobile/lib/core/network/check_in_service.dart`

## Scope of work

### A. shared-rust — กลไก sub-code แบบไม่หัก backward-compat
เพิ่มความสามารถให้ error envelope ส่ง code เฉพาะได้ (ทางแนะนำ: variant ใหม่
`AppError::ConflictCode { code: &'static str, message: String }` หรือ generic
`WithCode` — เลือก+justify; **ห้ามเปลี่ยน shape ของ envelope เดิม**
`{error: {code, message}}` และ variant เดิมทุกตัว map code เดิมเป๊ะ —
มี test คุมว่า `Conflict` ยังให้ `"CONFLICT"`)

### B. booking — ใช้ sub-code
- จุด emit duplicate ทั้ง 2 จุด (api pre-flight + repo 23505) → code
  **`DUPLICATE_CHECK_IN`** (message เดิมคงไว้)
- too-early / not-started **คง `CONFLICT`** เดิม
- `contracts/openapi/booking.yaml`: อัปเดต 409 ของ POST progress-reports —
  ระบุ code 2 แบบ + ความหมาย

### C. mobile client (ไฟล์เดียว)
- `_isDuplicateHour`: เช็ค `code == 'DUPLICATE_CHECK_IN'` เป็นหลัก ·
  **คง string-match เดิมเป็น fallback** (rollout ข้ามเวอร์ชัน: app ใหม่ + server เก่า)
  + comment ว่า fallback ถอดได้หลัง staging รัน server ใหม่ทั่ว
- test: code-based hit · fallback hit · too-early ไม่ hit ทั้งสองทาง

### Out of scope
ไล่เปลี่ยน error อื่นทั้งระบบเป็น sub-code (ทำเฉพาะ duplicate check-in นี้จุดเดียว)

## Hard rules (ย้ำ)
ไม่มี `.unwrap()`/`.expect()` ใน request path · `cargo fmt` + `clippy -D warnings`
clean · OpenAPI = source of truth (อัปเดต contract ก่อน code)

## Definition of Done
1. `cargo test --workspace` เขียว (รวม booking gated: duplicate จริงคืน
   `DUPLICATE_CHECK_IN` ทั้ง path pre-flight และ 23505 race · too-early ยัง
   `CONFLICT`) · shared-rust test: variant เดิม code ไม่ขยับ
2. `flutter analyze` + `flutter test` เขียว (test ใหม่ 3 เคสข้างบน)
3. booking.yaml อัปเดต + valid
4. `PROGRESS.md` log row
5. own PR off main — ไม่ merge เอง

## Review gate
2 agents (code + architecture) — จุดเพ่ง: envelope shape ไม่เปลี่ยน · ทุก call site
เดิมของ Conflict ไม่โดนผลข้างเคียง · fallback client ครบ
