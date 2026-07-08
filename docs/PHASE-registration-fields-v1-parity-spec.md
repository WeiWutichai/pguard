# PHASE spec — Registration fields = v1 parity (design + contract + backend + mobile)

> **เป้า:** ทำให้ field ที่เก็บตอนสมัคร (guard + customer) **เท่ากับ v1** ครบทั้ง 4 ชั้น
> ที่ field name ตรงกันเป๊ะ: design HTML → contract OpenAPI → backend (DB+repo) → mobile form
> **Worktree:** `feat/registration-fields-v1-parity` off `main` (`492dd1c` ขึ้นไป)
> **ใช้ terminal เดียว** (4 ชั้นผูกกัน — name ต้องตรง) · ห้ามแตะ `../guard-dispatch/` (v1 ref อ่านอย่างเดียว)
> **อ่าน design จริง `redesign-pguard/` ก่อนแก้** (กติกาโปรเจกต์)

---

## Authoritative field list (จาก v1 — verified)

แหล่งจริง v1 (อ่านอ้างอิงได้ ห้ามแก้): `../guard-dispatch/services/auth/src/models.rs`
(GuardProfileFormData/Row + SubmitCustomerProfileRequest/Row) +
`../guard-dispatch/frontend/mobile/lib/screens/{guard/guard_registration_screen,customer_registration_screen}.dart`

### Guard — ที่ v2 **ขาด** (ต้องเพิ่มให้เท่า v1)
| field | type | required | หมายเหตุ |
|---|---|---|---|
| `full_name` | TEXT | required (form) | v1 บังคับ · **DB+contract v2 ยังไม่มี** (design guard step1 มีช่องแล้ว) |
| `address` | TEXT | optional | ที่อยู่ guard · ขาดทั้ง DB/contract/design |
| `emergency_contact_name` | TEXT | optional | ผู้ติดต่อฉุกเฉิน · ขาดทั้ง 3 ชั้น |
| `emergency_contact_phone` | TEXT | optional | เบอร์ฉุกเฉิน (Thai phone format) |
| `emergency_contact_relationship` | TEXT | optional | ความสัมพันธ์ |

มีครบแล้ว (ไม่ต้องแตะ): gender, date_of_birth, years_of_experience, previous_workplace,
6 doc keys, bank_name, account_number, account_name

### Customer — ที่ v2 **ขาด**
| field | type | required | หมายเหตุ |
|---|---|---|---|
| `company_name` | TEXT | optional | design มีช่องแล้ว · **DB+contract ไม่มี** |
| `email` | TEXT | optional | design มีช่องแล้ว · DB+contract ไม่มี · validate `@`+`.`+len≥5 |
| `contact_phone` | TEXT | optional | **ขาดทั้ง DB/contract/design** (Thai phone format) |
| `full_name` | TEXT | optional | DB+contract มีแล้ว · **design ไม่มีช่อง → ต้องเพิ่มในdesign** |

มีครบแล้ว: `address` (required, min 10 chars)

---

## งานต่อชั้น (field name ต้องสะกดตรงกันทุกชั้น)

### A. Backend — `services/profile/`
1. Migration ใหม่ `contracts/db/migrations/profile/0004_registration_fields_v1_parity.sql`:
   - `ALTER TABLE profile.guard_profiles ADD COLUMN IF NOT EXISTS full_name TEXT, ADD COLUMN ... address TEXT, emergency_contact_name TEXT, emergency_contact_phone TEXT, emergency_contact_relationship TEXT` (nullable, additive — ไม่ rewrite)
   - `ALTER TABLE profile.customer_profiles ADD COLUMN ... company_name TEXT, email TEXT, contact_phone TEXT`
   - ตรวจ migrate.sh apply ได้ (numeric order) — index ไม่จำเป็น
2. `models.rs` + `repo/mod.rs`: เพิ่ม field ใน UpsertGuard/Customer + Row decode + UPSERT columns
   (ทุก SELECT ที่ decode เป็น Row ต้องรวม column ใหม่ — กัน decode panic) ·
   account_number masking เดิมคงไว้ · emergency_contact ถือเป็น PII → ถ้ามี access-audit/masking
   pattern ให้สอดคล้อง (เช็คว่า v2 มี masking เฉพาะ account ไหม — emergency phone ไม่ต้อง mask เว้นแต่ v1 ทำ)
3. validate: email (`@`+`.`+len≥5), phone Thai (10 หลักขึ้น 0) — ตาม validator เดิมของ repo

### B. Contract — `contracts/openapi/profile.yaml`
- `UpsertGuardProfileRequest` + `GuardProfile` (response) + admin update/response: เพิ่ม 5 field guard
- `UpsertCustomerProfileRequest` + `CustomerProfile` response: เพิ่ม company_name, email, contact_phone
- regen TS client web-admin (`pnpm gen:api`) + Dart ถ้ามี codegen target (commit generated)

### C. Design — `redesign-pguard/project/pguard/Mobile - Registration.html`
**อ่านโครง/ตัวแปร CSS เดิมก่อน** (.minput/.frow2/.seg2 + tokens) แล้วเพิ่มให้เข้าธีมเป๊ะ:
- Guard: เพิ่ม **ที่อยู่** (textarea) + บล็อก **ผู้ติดต่อฉุกเฉิน** (ชื่อ/เบอร์/ความสัมพันธ์)
  ในขั้น 1 หรือเพิ่ม sub-section (อย่าทำ step เกินจาก "4 ขั้น" ที่หัวเรื่องระบุ — แทรกใน step 1)
  + อัปเดต summary ขั้น 4 (ตรวจทาน) ให้โชว์ field ใหม่
- Customer: เพิ่ม **ชื่อ-นามสกุล** + **เบอร์ติดต่อ** (company/email มีแล้ว)
- คง bilingual `data-th`/`data-en` ครบทุก label ใหม่
- index.html/Coverage Matrix: ไม่ต้องเพิ่ม screen (ไฟล์เดิม) — แต่ถ้ามี field-list note อัปเดต

### D. Mobile — `apps/mobile/lib/features/auth` (หรือ registration)
- Guard registration form: เพิ่ม address + emergency contact (3) → ส่งใน submitGuardProfile
- Customer registration form: เพิ่ม full_name + contact_phone → ส่งใน submitCustomerProfile
- i18n TH/EN ครบ · validate ฝั่ง client (email/phone) · ส่ง field ใหม่ผ่าน generated/Api client
- ถ้า bank account มี mask-before-persist pattern เดิม — emergency phone ไม่ sensitive ไม่ต้อง mask

### E. Web-admin — `apps/web-admin`
- จอ guard detail (applicants/guards) + customer detail: **แสดง** field ใหม่ (read) ผ่าน generated client
  (admin เห็นข้อมูลสมัครครบ) — ไม่ต้องแก้เยอะ แค่ render เพิ่ม

## Hard rules
ไม่มี `.unwrap()`/`.expect()` request path · domain validate · migration additive nullable
(ไม่ rewrite/ไม่ NOT NULL บน table ที่มีข้อมูล) · generated client commit + ไม่ stale ·
mobile Riverpod + i18n ครบ · `cargo fmt`+`clippy -D warnings` · ไม่แตะ v1

## Definition of Done
1. `cargo test --workspace` เขียว · migrate.sh apply 0004 ได้ + idempotent · clippy/fmt clean
2. contract valid + regen client diff สอดคล้อง (CI stale-check เขียว)
3. `flutter analyze` + `flutter test` เขียว · field ใหม่ส่งถึง backend จริง (gated/contract test ยืนยัน)
4. web-admin `pnpm build`+`tsc` ผ่าน · จอ detail แสดง field ใหม่
5. **เทียบ design**: screenshot guard+customer registration หลังเพิ่ม field ใส่ใน PR (เข้าธีม)
6. **3-way parity table** ใน PR: v1 ↔ contract ↔ design ↔ mobile = ตรงกันทุก field
7. `PROGRESS.md` log row
8. own PR off main — ไม่ merge เอง · **`gh pr checks` เขียวครบก่อนรายงาน**

## Review gate
2 agents (code + architecture/design) — จุดเพ่ง: field name สะกดตรงกันทุกชั้น (DB↔contract↔design↔mobile) ·
migration additive ไม่พัง staging data · PII handling emergency/email สอดคล้อง pattern เดิม ·
design เข้าธีม (.minput/tokens) · ไม่มี field v1 ตกหล่น (เทียบ table)
