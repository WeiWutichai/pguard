# PHASE spec — Contract tests (Round 2-B: กัน contract drift ใน CI)

> **Slice:** เติม `tests/contract/` (ตอนนี้มีแค่ README scaffold) — พิสูจน์ว่า
> service จริงตรงกับ `contracts/openapi/*.yaml` + event payload ตรง
> `contracts/asyncapi/events.yaml` แล้วผูกเข้า CI
> **Worktree:** `feat/contract-tests` off `main` (`6301f3b` ขึ้นไป)
> **แตะได้:** `tests/contract/` + `.github/workflows/ci.yml` (เพิ่ม job เดียว) +
> PROGRESS.md — **ห้ามแตะ** services/* apps/* packages/* infra/k8s
> (มี 3 slice ขนาน: mobile capture · 409 sub-code · k8s) · **ใช้ terminal เดียว**
> **หมายเหตุ timing:** slice `feat/checkin-409-subcode` กำลังแก้ booking.yaml
> (409 ของ progress-reports) — ถ้า contract test fix รายละเอียดนั้นพอดี ให้เขียน
> เทียบ main ณ เวลา branch แล้วจดไว้ใน PR ว่า rebase หลัง slice นั้น merge

---

## เป้าหมายจริง (อย่าหลงรูปแบบ)

กันสองอย่าง: (1) **provider drift** — service แก้ response/พฤติกรรมแล้ว contract
ไม่อัปเดต (2) **consumer drift** — generated client คาด shape ที่ provider
ไม่ได้ให้แล้ว ทั้งคู่ต้องแตกใน CI ไม่ใช่ staging

**เลือกเครื่องมือได้** (README scaffold บอก Pact แต่ไม่บังคับ): consumer-driven
Pact เต็มรูป หรือ **provider verification จาก OpenAPI ตรงๆ** (เช่น schemathesis
/ dredd-style ยิง service จริงเทียบ spec) — เลือกแบบที่ maintenance ต่ำสุด
+ justify ใน PR; ห้าม mock จน test ไม่พิสูจน์อะไร

## Scope of work

### A. HTTP provider verification (อย่างน้อย 4 service สำคัญ)
- identity · booking · rating · chat (ครอบ auth flow + เส้นที่เพิ่งแตะใน
  กลุ่ม A) — ยิงกับ **service จริงบน stack จริง** (reuse
  `tooling/scripts/e2e-stack-up.sh` + seed เดิม — อย่า reinvent harness)
- ครอบทั้ง happy path + error envelope (`{error:{code,message}}`) + auth
  required ตรงตาม `security:` ใน spec
- จุดที่เคยเจอ drift จริง (จาก audit): rating `getGuardRatings` เคยเขียน
  public ทั้งที่ edge protect — test แบบนี้แหละที่ต้องจับได้

### B. Event contract (เบากว่า)
- Validate payload จริงที่ service emit (จาก outbox/NATS บน stack จริง) เทียบ
  JSON Schema ใน `contracts/asyncapi/events.yaml` — อย่างน้อย
  `booking.job_accepted` + `booking.progress_reported` + `user.approved`
- Envelope ครบ: `event_id, event_type, occurred_at, correlation_id, payload`

### C. Consumer side (ขั้นต่ำที่คุ้ม)
- Generated TS client (web-admin) build против spec อยู่แล้วผ่าน tsc —
  เพิ่ม check ว่า **generated clients ใน repo ไม่ stale**: regen จาก contract
  แล้ว byte-diff ต้องว่าง (จับคนแก้ contract แล้วลืม regen)

### D. CI job
- `contract-tests` job ใน ci.yml: stack-up → รัน suite → fail = แดง
- ระวังเวลา: ถ้า stack-up หนักเกิน ให้ scope service ที่ boot (document)

### Out of scope
Pact broker / can-i-deploy workflow (จด TODO) · ครบทั้ง 10 services (เริ่ม 4 +
วาง pattern ให้เพิ่มง่าย — README อธิบายวิธีเพิ่ม service ถัดไป)

## Definition of Done
1. Suite รันเขียว local บน stack จริง (บันทึกผลใน PR) + จับ drift ได้จริง —
   **พิสูจน์ด้วย mutation test**: แก้ contract ชั่วคราว 1 จุด (เช่น เปลี่ยน
   required field) → suite ต้องแดง → revert (แสดง log ใน PR)
2. CI job เขียวบน GitHub Actions จริง
3. stale-client check ทำงาน (regen diff ว่าง)
4. `tests/contract/README.md` อัปเดตจาก scaffold → วิธีรัน + วิธีเพิ่ม service
5. `PROGRESS.md` tick กลุ่ม B ข้อ contract tests + log row
6. own PR off main — ไม่ merge เอง

## Review gate
2 agents (code + architecture) — จุดเพ่ง: test พิสูจน์จริงไม่ใช่ tautology
(เทียบกับ spec ไม่ใช่เทียบกับตัวเอง) · ไม่แตะ service code · CI time budget
