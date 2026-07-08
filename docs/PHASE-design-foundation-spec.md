# PHASE spec — Design foundation (tokens จริง + Tailwind theme + component library + admin shell)

> **Keystone ของ web-admin rebuild:** ปิด root cause ที่ web-admin ถูก build โดยไม่เคย
> อ้าง hi-fi design — สร้างฐาน (tokens + theme + ชุด component + shell) ที่ทุกจอจะใช้ต่อ
> **ต้อง merge ก่อน slice rebuild จอใดๆ** (ทุกจอ depend ฐานนี้)
> **Worktree:** `feat/design-foundation` off `main` (`9bb5d8c` ขึ้นไป)
> **ใช้ terminal เดียว** · ห้ามแตะ services/* · ห้ามแตะ `../guard-dispatch/`

---

## Source of truth (อ่านให้ครบก่อนเขียนโค้ด)

`redesign-pguard/project/pguard/` — hi-fi design จริง:
- `tokens.css` — color ramps + semantic aliases + light/dark (เอาค่าจริงจากนี่ **ห้ามเดา**)
- `admin.css` — component styles (button/input/kpi/panel/table/badge/chip/toggle/tab/avatar/modal/search)
- `admin-shell.js` — โครง sidebar (4 nav groups) + topbar
- `Design System.html` — reference รวม + typography scale
- `Admin - Dashboard.html` — ตัวอย่าง shell + layout จริง

**ค่าหลักที่ต้องตรง (จาก inventory):**
- Brand anchor `#0E3B2E` (green-900) · interactive `#1FA971` (green-500) · hover `#15885B`
  · accent `#F59E0B` — **ไม่ใช่** `#16a34a` (Tailwind green-500) ที่ของเดิมใช้ผิด
- Neutrals green-tinted ramp (n-0..n-950), semantic + status (active/working/offline + ring)
- Font: **IBM Plex Sans Thai** + IBM Plex Sans (ของเดิมเป็น system-ui) · type scale
  (display 44 / h1 34 / h2 27 / h3 21 / lg 18 / base 16 / sm 14 / xs 12 / 2xs 11) ·
  line-height base 1.62 (Thai) · tracking 0.01em
- Spacing 4px scale (sp-1..sp-12) · radius (xs4..2xl18,full) · shadows (xs..xl,brand,accent)

## Scope of work

### A. Design tokens — extract จริง (เลิก placeholder)
1. `apps/design-tokens/` — เขียน `extract.mjs` (หรือ script) อ่าน `tokens.css` จาก
   redesign → ออก `tokens.css` + `tokens.ts` + `tokens.dart` **ครบทุก token**
   (ตอนนี้เป็น stub subset — README ยอมรับว่ายังไม่ extract) · pin ใน
   `tooling/codegen/generate.sh` (target ใหม่) + CI stale-check (regen→diff ว่าง)
2. **ห้าม hardcode hex ใน web-admin อีก** — ทุกสีมาจาก token
3. Mobile ใช้ tokens.dart อยู่แล้ว — ระวังไม่ทำ Flutter พัง (ค่าเดิมเป็น subset;
   ถ้า key เปลี่ยนต้องเช็ค `apps/mobile` ใช้ key ไหน — additive ปลอดภัย, rename ต้อง audit)

### B. Tailwind theme (web-admin)
1. `apps/web-admin/app/globals.css` `@theme` — map ทุก token จาก tokens.css จริง
   (color ramps เต็ม + semantic aliases + typography + spacing + radius + shadow) ·
   light/dark ผ่าน CSS var (tokens.css มี dark mode override แล้ว — port มา)
2. โหลด IBM Plex Sans Thai (next/font หรือ self-host — เลือก+justify; bilingual)
3. ลบสี hardcode `#16a34a`/`#f3f5f4` ที่ผิด palette ออก

### C. Component library `apps/web-admin/src/components/ui/`
port จาก `admin.css` ให้ตรง spec (ดู inventory สำหรับ padding/radius/สี exact):
- `Button` (primary/secondary/ghost/accent/danger + sizes, min-touch 44px)
- `Input`/`Textarea` (focus ring `rgba(31,169,113,.45)`, error state)
- `Badge` (green/amber/red/blue/gray) · `Chip` (active `#0E3B2E`) · `Tab` (pill counter)
- `KpiCard` (mono 30px value, border-left, icon bg) · `Panel` (header/body)
- `Table` (uppercase 11.5px header, hover sunken) · `Avatar` (+ status dot)
- `Toggle` · `Modal` (overlay blur, radius 14px) · `SearchField`
- ทุกตัว: รองรับ dark mode + i18n-agnostic (รับ children/props ไม่ฝัง string)

### D. Admin shell (`Sidebar` + `Topbar` + layout)
1. `Sidebar` 248px: logo pguard (p เป็น brand-int) + **4 nav groups** ตาม
   admin-shell.js (ภาพรวม / การเงิน&งาน / การสื่อสาร / ระบบ) + active state
   `#0E3B2E` ทึบ (ของเดิม `bg-brand/10` จาง) + badge/count + foot (avatar+role+theme toggle)
2. `Topbar` 62px: page title+subtitle · search 260px · notification bell (red dot) ·
   lang toggle ไทย/EN (reuse i18n เดิม) · user menu popover (logout ผ่าน CSRF เดิม)
3. nav items ชี้ route ที่ **มีจริงตอนนี้** (dashboard/applicants/guards/customers/
   reviews/wallet/pricing/map/activity/settings) — จอที่ยังไม่ build (bookings/tasks/
   calls/chat/broadcast/profile/reports/operations/automation/...) ใส่เป็น nav item
   ได้แต่ชี้ `ApiGapPage`/coming-soon (อย่าทำ dead link) — จด list จอที่เหลือใน PR
   (จะ rebuild + build ใหม่ใน slice ถัดๆ ไป)

### E. ใช้ shell ใหม่กับ layout
`app/(dashboard)/layout.tsx` ใช้ Sidebar/Topbar ใหม่ — จอเดิมทั้งหมดต้อง render
ใต้ shell ใหม่ได้ (เนื้อในจอยังเป็นของเดิมในเฟสนี้ — แค่กรอบ+token เปลี่ยน;
จอจะถูก rebuild ทีละ slice หลังจากนี้)

### Out of scope (slice ถัดไป)
- Rebuild เนื้อในแต่ละจอให้ตรง mockup เป๊ะ (component+layout per screen)
- 15 จอที่ยังไม่มี route (+ backend endpoint ที่อาจยังไม่มี — หลายจอเป็น API-gap)

## Hard rules (web-admin เดิม)
App Router · TS strict · cookie auth (httpOnly, ไม่ localStorage) · CSRF บน write ·
generated client เท่านั้น (ไม่ raw fetch) · lucide icons · i18n TH/EN ครบ ·
`cn()` · ไม่เพิ่ม dep หนักเกินจำเป็น (justify)

## Definition of Done
1. `pnpm build` ✅ · `pnpm lint` · `tsc --noEmit` strict ✅ · ทุกจอเดิม render
   ใต้ shell ใหม่ไม่ crash
2. token extract script รันได้ + idempotent (regen diff ว่าง) + CI stale-check เขียว ·
   mobile `flutter analyze` ไม่พัง (tokens.dart)
3. **เทียบสายตา**: screenshot dashboard + login + 1 list page ใส่ใน PR เทียบ mockup
   (สี/ฟอนต์/sidebar ตรง) — ใช้ Playwright screenshot หรือ manual
4. ไม่มี hardcoded hex นอก token (grep ยืนยัน)
5. `PROGRESS.md` log row + ระบุว่านี่คือ foundation, จอเนื้อในจะ rebuild ต่อ
6. own PR off main — ไม่ merge เอง · **`gh pr checks` เขียวครบก่อนรายงาน**

## Review gate
2 agents (code + design-critique/frontend) — จุดเพ่ง: token ตรง tokens.css จริง
(สุ่มเช็ค 5 ค่า) · ไม่มี hardcoded hex · shell ตรง admin.css (sidebar 248/active
#0E3B2E/4 groups) · dark mode ใช้ได้ · ไม่ทำ mobile tokens.dart พัง · จอเดิมไม่ regress functional
