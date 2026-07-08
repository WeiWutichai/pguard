# PHASE spec — Mobile: guard rating card + customer review screen (2 quick wins)

> ปลด placeholder "รอ API" 2 จุดในมือถือ — **endpoint มีอยู่แล้ว + design มีอยู่แล้ว** แค่ wire/สร้างจอ
> **Worktree:** `feat/mobile-rating-review` off `main` (`758eb14`+)
> **แตะเฉพาะ `apps/mobile/`** · ใช้ terminal เดียว · ห้ามแตะ `../guard-dispatch/`
> **อ่าน design จริงก่อนทั้ง 2 ไฟล์ (verified — มี mockup จริงครบ):**
> - rating card guard → `redesign-pguard/project/pguard/Mobile - Guard App.html` section **"รีวิวที่ได้รับ / Ratings & reviews"**
> - จอรีวิวลูกค้า → `redesign-pguard/project/pguard/Mobile - Customer App.html` section **"รีวิว"**

---

## Verified (อย่าเดา — เช็คมาแล้ว)
- `GET /guards/{id}/ratings` — `contracts/openapi/rating.yaml:88` ✅
- `POST /assignments/{id}/review` — `contracts/openapi/rating.yaml:43` ✅ (body: overall_rating + category ratings optional + review_text)
- **จอรีวิวลูกค้า mockup** (`Mobile - Customer App.html` "รีวิว"): `class="stars"` (★ overall 5 ดวง) +
  "ให้คะแนนแยกหมวด (ไม่บังคับ)" → `catrate`/`ministars` หมวด ตรงเวลา/มืออาชีพ/สื่อสาร/ความเรียบร้อย
  (= category ratings ใน contract) + ปุ่ม "ส่งรีวิว" → **build ตาม element/หมวดเหล่านี้เป๊ะ**
- **rating card guard mockup** (`Mobile - Guard App.html` "รีวิวที่ได้รับ"): layout คะแนนเฉลี่ย+รายการรีวิว
  → wire ค่าจริงเข้า layout นี้ ไม่สร้างใหม่

## Scope

### A. Guard rating card (wire ของจริงเข้า layout mockup "รีวิวที่ได้รับ")
- จุดที่โชว์ "—"/placeholder: card คะแนน guard (ฝั่ง guard app)
- ดึง `GET /guards/{id}/ratings` ผ่าน generated/Api client → แสดง avg ★ + จำนวนรีวิว + รายการรีวิว
  ตาม layout "รีวิวที่ได้รับ" ใน `Mobile - Guard App.html` · controller ใน `core/controllers/`
  (Riverpod, fake-injectable) · ไม่มี polling
- error/empty: ยังไม่มีรีวิว = state ว่างที่ดีไซน์ไว้ (อย่าโชว์ 0.0 ลวง)

### B. Customer review screen (สร้างจอใหม่ตาม design)
- หลังงาน `completed` → customer เข้าจอรีวิว: ★ overall (required) + category (punctuality/
  professionalism/communication/appearance — optional ตาม contract) + review_text → `POST /assignments/{id}/review`
- **ทำตาม mockup `Mobile - Customer App.html` "รีวิว" เป๊ะ** (layout/ดาว/ปุ่ม/ธีม) — อ่านก่อนเขียน
- entry point: จาก job completion summary / live status เมื่อ completed (ตรวจ flow เดิมว่าจอ
  completion ต่อไปไหน — ต่อจากนั้น) · กันรีวิวซ้ำ (1 review/assignment ตาม contract — handle 409/ปุ่ม disable ถ้ารีวิวแล้ว)
- controller pattern เดิม · i18n TH/EN ครบ

### Out of scope
- FCM push (ต้อง Firebase project + google-services.json ก่อน — แยก slice, รอ wei สร้าง project)
- admin aggregate KPIs (slice แยก ฝั่ง backend)

## Hard rules
Riverpod codegen · logic ใน controller · ไม่ Timer.periodic · generated/Api client เท่านั้น ·
ไม่เพิ่ม dependency · i18n TH/EN ทุก string

## Definition of Done
1. `flutter analyze` clean · `flutter test` เขียว + test ใหม่ (rating fetch+empty · review submit+dup-guard)
2. rating card แสดงค่าจริงจาก endpoint · review submit ถึง backend จริง (fake-verified + ถ้ามี contract/e2e ยืนยัน)
3. **screenshot จอรีวิวเทียบ mockup** ใส่ใน PR (เข้าธีม)
4. `PROGRESS.md` log row
5. own PR off main — ไม่ merge เอง · **`gh pr checks <n> --watch` เขียวครบก่อนรายงาน** (repo ไม่มี branch protection)

## Review gate
2 agents (code + flutter/design) — จอรีวิวตรง mockup · no polling · controller purity · กันรีวิวซ้ำ
