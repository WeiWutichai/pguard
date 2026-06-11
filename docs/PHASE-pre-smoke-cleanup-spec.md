# PHASE spec — Pre-smoke cleanup (4 follow-up เล็กก่อน smoke test รอบใหญ่)

> รวม follow-up ที่จดค้างจาก audits — ชิ้นเล็ก 4 เรื่องคนละโซน จบใน PR เดียว
> **Worktree:** `feat/pre-smoke-cleanup` off `main` (`ebbd88e` ขึ้นไป)
> **ห้ามแตะ:** `packages/shared-rust` `services/api-gateway` `services/chat`
> (slice redis-reconnect ขนาน) · `services/identity` (slice auth-tests ขนาน) ·
> `../guard-dispatch/` · **ใช้ terminal เดียว**

---

## 1. Tighten dup-409 assertion (contract tests) — REQUIRED ที่ PR #32 จดเอง
`tests/contract/events/events.contract.test.ts` (~110): assertion หลวม
`["CONFLICT","DUPLICATE_CHECK_IN"]` → PR #31 merge แล้ว ให้ tighten เป็น
`["DUPLICATE_CHECK_IN"]` เป๊ะ + ลบ comment rollout

## 2. FCM_DISABLED เป็น value-aware (bug แฝงเดิม)
`services/notification/src/main.rs:59` gate แบบ **presence-based**
(`env::var(...).is_ok()`) — ตั้ง `"false"` ก็ยังได้ NoopPusher เงียบๆ และ
compose.prod ตั้ง `FCM_DISABLED: ${FCM_DISABLED:-false}` = prod push ปิดถาวร
โดยไม่รู้ตัว · k8s base ก็สืบทอด bug นี้ (`infra/k8s/base/notification.yaml`)
- แก้เป็น value-aware ผ่าน `shared::config::parse_env_bool` (แพตเทิร์นเดียวกับ
  SMS_DISABLED ที่แก้ไปแล้ว — ดู `services/otp/src/sms.rs:91`)
- เช็คทุกที่ที่ตั้ง FCM_DISABLED (compose.prod/staging/e2e, k8s base+overlays)
  ให้ semantics ใหม่ถูก: e2e/dev = "true" (ปิด) · prod/staging default = ไม่ปิด
  แต่ FCM creds ยังไม่มีจริง → ตรวจว่า pusher จริง fail ยังไงเมื่อไม่มี creds
  (ต้อง fail ชัดตอน boot หรือ degrade มี log — ห้ามเงียบ); ถ้ายังไม่มี creds
  ให้ staging ตั้ง "true" explicit ไปก่อน + จดไว้
- tests ตามแพตเทิร์น sms_disabled เดิม

## 3. rating `guard_ratings` เพิ่ม AuthUser (defense-in-depth)
`services/rating/src/api/mod.rs:100` — endpoint เดียวที่พึ่ง edge อย่างเดียว
(contract เขียน bearerAuth แล้วจาก PR #25 แต่ service ไม่ validate เอง)
- เพิ่ม `AuthUser` extractor (role ไหนก็ได้ — สาธารณะภายในระบบ) ให้ตรง contract
- เช็ค caller ภายใน: booking internal client เรียก `/internal/guards/{id}/rating-summary`
  (คนละ route — ไม่กระทบ) · contract test ของ rating (PR #32) ยิงผ่าน gateway
  มี token แล้ว — ยืนยันไม่แดง · e2e env-gated rewrite path (ดูข้อ 4)
- gated test: ไม่มี token ตรงถึง service = 401

## 4. ถอด e2e env-gated rewrites (web-admin)
`apps/web-admin/next.config.ts` — rewrites `PGUARD_RATING_URL`/`PGUARD_PRESENCE_URL`
ใส่ไว้สมัย gateway ยัง 404 (ปิดไปแล้วใน PR #25)
- ถอด rewrites + env ที่เกี่ยว · ไล่ `tests/e2e` ที่อ้าง (CI `e2e-web` job ตั้ง
  env พวกนี้ไหม — ถ้าตั้ง ให้ถอดด้วย) → e2e ต้องวิ่งผ่าน gateway ล้วน
- ระวังข้อ 3 ทำให้ rating ตรง (:3007) ต้องมี token — ถอด rewrite แล้วทุกอย่าง
  ผ่าน gateway จึงไม่กระทบ แต่**รัน e2e suite เต็มยืนยัน** (สองข้อนี้ต้องเขียวพร้อมกัน)

## Definition of Done
1. ทุก suite ที่แตะรันเขียวจริง: contract tests (stack จริง) · e2e Playwright
   เต็ม (ผ่าน gateway ล้วน) · `cargo test --workspace` · notification tests
2. clippy/fmt clean · compose config ผ่าน · k8s `kustomize build` ผ่าน (ถ้าแตะ)
3. `PROGRESS.md`: ปิด follow-up 4 ข้อ + log row
4. own PR off main — ไม่ merge เอง · **`gh pr checks` เขียวครบก่อนรายงาน**

## Review gate
2 agents (code + architecture) — จุดเพ่ง: FCM semantics ใหม่ไม่เปิด push
โดยไม่มี creds เงียบๆ · e2e ไม่เหลือ path ข้าม gateway · ไม่แตะโซน slice ขนาน
