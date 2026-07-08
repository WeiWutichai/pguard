# PHASE spec — Design: เพิ่มจอจัดการราคา (mobile) ใน redesign-pguard

> เพิ่ม mockup **จัดการราคา (admin) เวอร์ชัน mobile** เข้า design — ตอนนี้มีเฉพาะ
> `Admin - Pricing.html` (web) · v1 ก็ทำเฉพาะ web (`../guard-dispatch/frontend/web/app/(dashboard)/pricing/page.tsx`)
> นี่คือ design-only (ไฟล์ HTML mockup) — **ไม่แตะโค้ด app/service**
> **Worktree:** `feat/design-mobile-pricing` off `main` (`758eb14`+) · ใช้ terminal เดียว
> **ห้ามแตะ `../guard-dispatch/`** (อ่านอ้างอิงได้)

---

## หลักฐาน (verified — อย่าเดา)
- design มี `redesign-pguard/project/pguard/Admin - Pricing.html` (web, 8.9KB): "เพิ่มบริการ" ·
  "ค่าบริการพื้นฐาน (฿/ชม.)" (0 ≤ x ≤ 1,000,000) · "ชั่วโมงขั้นต่ำ" · "แก้ไขบริการ" · "กฎราคา" (ยังไม่เปิด)
- v1 web pricing fields: `name` · `base_fee` · `min_hours` + create/update/delete
- **mobile v1 ไม่มีจอ pricing** → จอนี้เป็นของใหม่ (design pass), อิงเนื้อจาก Admin-Pricing + v1

## โครง mobile mockup (clone ให้ตรง — verified จาก `Mobile - More Screens.html`)
- `<head>`: 3 stylesheet เป๊ะ — `tokens.css` · `proto/app.css` · `mobile-canvas.css`
- device frame: `<div class="canvas"><div class="col"><div class="lab"><span class="tag">N</span><h2 data-th>…</h2></div>
  <div class="phone"><div class="notch"></div><div class="screen"><div class="statusbar"><span>9:41</span><span>●●● 5G ▮</span></div>
  <div class="body"><div class="scroll"> … </div></div></div></div></div></div>`
- ฟอร์ม: `.mfield > label[data-th]/[data-en lang-hide] + input.minput` · ปุ่ม `.cta .cta-green` (admin/จัดการ
  ใช้ green ตาม theme) · list card ใช้คลาสที่มีใน proto/app.css (อ่าน proto/app.css ก่อนเลือกคลาส — อย่าคิดคลาสเอง)
- **bilingual ครบ**: ทุก label มี `data-th` + `data-en lang-hide` (pattern เดิม)

## Scope — สร้าง `Mobile - Pricing.html` (2–3 จอใน 1 ไฟล์)
1. **จอ list บริการ**: card ต่อบริการ — ชื่อบริการ · ค่าบริการพื้นฐาน `฿X/ชม.` (mono font) ·
   ชั่วโมงขั้นต่ำ · ปุ่มแก้ไข/ลบ · ปุ่ม "เพิ่มบริการ" (cta-green) ล่างสุด
2. **จอเพิ่ม/แก้ไขบริการ**: mfield — ชื่อบริการ · ค่าบริการพื้นฐาน (฿/ชม., mono, helper "0 ≤ x ≤ 1,000,000") ·
   ชั่วโมงขั้นต่ำ · ปุ่มบันทึก (cta-green) — mirror Admin-Pricing ฝั่ง field
3. (optional) จอ "กฎราคาตามช่วงเวลา" = empty/coming-soon state ตาม Admin-Pricing ("กฎราคายังไม่เปิดใช้งาน")
- ตัวเลขในตัวอย่างใช้ค่าสมเหตุผล (เช่น รปภ.ทั่วไป ฿150/ชม. ขั้นต่ำ 6 ชม.) — mockup เป็นภาพ ไม่ผูก data จริง

## ผูกเข้า project
- `index.html`: เพิ่ม entry ใน array กลุ่ม mobile — `['Mobile - Pricing.html','tag-icon-ที่มี','จัดการราคา','service rates · base fee/hr']`
  (ดู pattern บรรทัด 137-152; เลือก icon จากชุดที่ index ใช้อยู่ อย่าใส่ icon ใหม่ที่ไม่มี)
- `Coverage Matrix.html`: ถ้ามีตาราง endpoint↔screen ให้เพิ่มแถว pricing (mobile) — optional ถ้าโครงเอื้อ

## ⚠️ Cloud sync (อ่าน)
ไฟล์นี้อยู่ใน local `redesign-pguard/` = source of truth. การให้ขึ้น **cloud Claude Design project**
(`claude.ai/design/p/8d6b9ed6…`) เป็น **ขั้น sync แยก** (DesignSync ต้อง `/login`) — wei จะ sync เองหลัง merge
ไม่ใช่ scope ของ slice นี้

## Definition of Done
1. `Mobile - Pricing.html` render ได้ (เปิดในเบราว์เซอร์ไม่พัง) · 3 stylesheet ลิงก์ถูก ·
   device frame + components ตรง mobile mockup เดิม (ไม่ประดิษฐ์คลาสใหม่)
2. bilingual TH/EN ครบทุก label · index.html มี entry ใหม่ + เปิดลิงก์ถึงได้
3. **screenshot จอ list + จอเพิ่ม/แก้ไข ใส่ใน PR** เทียบ `Admin - Pricing.html` (เนื้อตรง) + mobile theme
4. ไม่แตะ `apps/` `services/` `contracts/` — **design-only** (เฉพาะ `redesign-pguard/`)
5. `PROGRESS.md` log row (ระบุ: mobile pricing mockup ใหม่ + ต้อง sync cloud แยก)
6. own PR off main — ไม่ merge เอง · `gh pr checks <n> --watch` เขียวก่อนรายงาน

## Review gate
1 agent design-critique พอ (design-only, ไม่มี logic) — เพ่ง: ใช้ tokens/คลาสจริงจาก proto/app.css ·
device frame ตรง mobile system · เนื้อ field ตรง v1/Admin-Pricing · bilingual ครบ · ไม่ประดิษฐ์คลาส/icon ใหม่
