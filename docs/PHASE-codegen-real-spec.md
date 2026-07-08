# PHASE spec — Codegen จริง (Dart client + Rust event types จาก contracts)

> **กลุ่ม B:** `tooling/codegen/generate.sh` มี TS target จริงแล้ว ที่เหลือเป็น
> TODO echo — ทำ 2 target ที่คุ้มให้จริง + stale-check ใน CI
> **Worktree:** `feat/codegen-real` off `main` (`da4e29a` ขึ้นไป)
> **เขตไฟล์:** `tooling/codegen/` · `apps/mobile/lib/api/` (โฟลเดอร์ generated
> ใหม่เท่านั้น — **ห้ามแตะ lib อื่นของ mobile**) · `packages/shared-events/`
> (โฟลเดอร์ generated + wiring) · ci.yml (job/step เดียว) · PROGRESS.md
> มี 2 slice ขนาน (security: NATS/shared-rust bootstrap/CI audit job ·
> load/chaos: tests/load+observability) — **ci.yml อาจชนกับ security slice:
> เขียน step ต่อท้ายแบบ additive จะ merge ง่าย** · **ใช้ terminal เดียว**

---

## หลักคิด — ทำเฉพาะที่คุ้ม อย่าฝืนทำครบ 4 target

| Target | ตัดสิน |
|---|---|
| TS client (web-admin) | ✅ มีแล้ว + stale-check จาก PR #32 — ไม่แตะ |
| **Dart client (mobile)** | **ทำ** — แต่ adoption เป็น out of scope (ดูล่าง) |
| **Rust event serde types (shared-events)** | **ทำ** — ผูก asyncapi ↔ code จริง |
| Rust Axum handler stubs | **ข้าม + เขียนเหตุผลใน README**: services เขียนมือเสร็จหมดแล้ว + contract tests (PR #32) ทำหน้าที่ verify provider ตรง spec อยู่แล้ว — stub gen ตอนนี้ = churn ไม่มีประโยชน์; เก็บ TODO ไว้สำหรับ service ใหม่ในอนาคต |

## Scope of work

### A. Dart client
1. เลือก generator (openapi-generator dart-dio หรือเทียบเท่า — pin version ใน
   README + script) → generate จาก `contracts/openapi/*.yaml` ลง
   `apps/mobile/lib/api/generated/` (commit ผลลัพธ์ตามแพตเทิร์น TS)
2. **Adoption = out of scope**: โค้ด mobile เดิมใช้ hand-written client ต่อไป —
   generated มีไว้ให้ feature ใหม่เริ่มใช้ + เป็น compile-time proof ว่า contract
   ปัจจุบัน representable ใน Dart; ใส่ README ใน folder บอกสถานะนี้ชัดๆ
3. `flutter analyze` ต้องผ่านรวม generated (ถ้า generator ออก code ที่ analyze
   ไม่ผ่าน = ปรับ config/exclude พร้อม justify)

### B. Rust event types
1. Generate serde types จาก `contracts/asyncapi/events.yaml` ลง
   `packages/shared-events/src/generated/` (เลือกเครื่องมือ/เขียน generator
   เล็กจาก JSON Schema — justify; typify เป็น candidate)
2. **พิสูจน์ตรงกับ hand-written เดิม**: ทดสอบ serde roundtrip — payload ตัวอย่าง
   จริงของทุก event type (envelope + payload) parse ได้ทั้งสอง represent
   เหมือนกัน; **อย่าสลับ services ไปใช้ generated ใน slice นี้** (จด follow-up)
   — ขั้นนี้ generated คือ contract-lock: ถ้าใครแก้ events.yaml แล้ว regen
   ไม่ตรง hand-written → test แดง = จับ drift
3. `cargo test --workspace` เขียว · clippy/fmt clean (รวม generated — ถ้า
   generated ไม่ clean ใช้ `#[allow]` ระดับ module + justify)

### C. Stale-check ใน CI
- ขยายแนว `tests/contract/check-generated-clients.sh` (PR #32): regen dart +
  rust-events แล้ว `git diff --exit-code` — ใส่เป็น step additive ใน job
  ที่เหมาะ (contract-tests job หรือ job ใหม่เบาๆ) · เครื่องมือ generator ต้อง
  pin version และรันได้บน CI runner (ถ้าต้องใช้ java/docker ระบุ+จัดการ)
- `generate.sh`: target ที่ทำแล้วเปลี่ยนจาก echo TODO → รันจริง; stubs target
  เปลี่ยน TODO → SKIPPED(เหตุผล)

### Out of scope
mobile adopt generated client · services adopt generated event types ·
Rust Axum stubs (ตามตาราง)

## Definition of Done
1. `./tooling/codegen/generate.sh` รันจบ: TS + Dart + rust-events จริง
   (idempotent — รันซ้ำ diff ว่าง)
2. `flutter analyze` clean · `cargo test --workspace` เขียว (รวม roundtrip
   drift-lock tests) · clippy/fmt clean
3. CI stale-check เขียวบน GitHub Actions จริง
4. README codegen อัปเดต: target matrix + วิธีเพิ่ม spec ใหม่ + เหตุผล skip stubs
5. `PROGRESS.md` tick codegen + log row
6. own PR off main — ไม่ merge เอง

## Review gate
2 agents (code + architecture) — จุดเพ่ง: generated ไม่ leak เข้า runtime ที่ใช้
อยู่ (zero behavior change) · generator pinned/reproducible · drift-lock test
ไม่ tautology (เทียบกับ hand-written จริง ไม่ใช่เทียบกับตัวเอง)
