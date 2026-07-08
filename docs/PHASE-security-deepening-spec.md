# PHASE spec — Security deepening (NATS authz + cargo audit + rotation runbook + pen-test checklist)

> **กลุ่ม B (Round 3-C):** ปิด follow-up ที่ NATS signed-envelope slice จดไว้ +
> dependency audit + ops docs
> **Worktree:** `feat/security-deepening` off `main` (`da4e29a` ขึ้นไป)
> **ใช้ terminal เดียว** · ห้ามแตะ `../guard-dispatch/` · มี 2 slice ขนาน
> (load/chaos: `tests/load`+`infra/observability` · codegen: `tooling/codegen`+
> `packages/*/src/generated`+`apps/mobile/lib/api`) — **อย่าแตะเขตพวกนั้น**

---

## สถานะวันนี้ (จาก audit)

- NATS **ไม่มี server-side auth เลย** — พึ่ง network isolation + signed envelope
  (HMAC-SHA256, `EVENT_SIGNING_SECRET`) อย่างเดียว: pod/container ไหนหลุดเข้า
  network = subscribe/publish ได้ทุก subject (signed envelope กัน forge ได้
  แต่กัน eavesdrop/replay-DoS ไม่ได้)
- `cargo audit`/`deny` ไม่มีใน CI · **`Cargo.lock` ไม่ commit** (gitignored)
- Secrets ครบใน `${VAR:?}` แต่ไม่มี rotation runbook · identity มี
  `token_revocation_version` ใช้ประกอบ JWT-secret rotation ได้
- v1-audit/03-security มี 15-risk matrix ใช้เป็นฐาน checklist ต่อ

## Scope of work

### A. NATS authorization (ชิ้นหลัก)
1. **เปิด NATS authz จริง**: user ต่อ service (หรือ 2 account:
   services/monitoring) ใน nats server config — รหัสผ่านจาก env `${VAR:?}`
   ตามแพตเทิร์น secrets เดิม; แก้ compose.prod + `.env.staging.example` +
   `infra/k8s` (base nats config + secrets example — slice k8s merge แล้ว
   อัปเดตให้สอดคล้อง)
2. **Subject permissions ต่อ service** ตาม publish/subscribe matrix จริง
   (อ่านจาก `services/*/src/events` — เช่น booking publish
   `pguard.events.booking.*` เท่านั้น · notification subscribe ได้ทุก
   `pguard.events.>` แต่ publish ไม่ได้ ฯลฯ) — least privilege, เขียน matrix
   ลง `contracts/asyncapi/` หรือ docs ให้ตรวจได้
3. Services ต่อ NATS ด้วย creds ของตัวเอง (shared-rust NATS bootstrap รับ
   user/pass จาก env — backward compat: ไม่ตั้ง = ต่อแบบเดิมได้ใน dev)
4. Tests: gated integration — service ที่ไม่มีสิทธิ์ publish subject แปลก
   ต้องโดน reject (พิสูจน์ ACL ทำงานจริง ไม่ใช่แค่ config ผ่าน)
5. **Migration path บน staging ต้องไม่ down**: document ลำดับ rollout
   (เปิด auth ที่ nats + ใส่ creds ทุก service พร้อมกันใน deploy เดียว — มี
   restart วินาทีระดับ ok แต่ระบุใน PR)

### B. Dependency audit ใน CI
1. **Commit `Cargo.lock`** (ปลด gitignore) — จำเป็นทั้ง reproducible build
   และ audit; ระบุใน PR ว่า workspace นี้เป็น binary services (lock ควร commit
   ตาม Rust convention)
2. CI job `cargo audit` (RustSec) — แดงเมื่อมี vulnerability ระดับสูง; ignore
   list ต้องมีเหตุผล+วันหมดอายุ · พิจารณา `cargo deny` (licenses/bans) ถ้า
   เพิ่มได้ถูก (justify ถ้าข้าม)
3. npm side: `pnpm audit` web-admin + tests (non-blocking warn ก่อน — justify
   threshold)

### C. Docs (ops)
1. `docs/SECRET-ROTATION.md` — runbook ต่อ secret: JWT_SECRET (ผูก
   token_revocation_version + dual-secret window ถ้า code รองรับ — ถ้าไม่
   ให้บอกตรงๆ ว่า rotation = force re-login ทั้งระบบ) · SERVICE_JWT_SECRET ·
   EVENT_SIGNING_SECRET · DB/MinIO/TURN/NATS — ลำดับคำสั่งจริงบน VPS ต่อตัว
2. `docs/PENTEST-CHECKLIST.md` — ต่อยอด 15-risk matrix v1-audit: รายการทดสอบ
   เป็นข้อๆ (auth bypass, IDOR ทุก resource, rate-limit, WS hijack, S3
   presign abuse, NATS access) + สถานะ closed/open + วิธี verify แต่ละข้อ

### Out of scope
จ้าง pen-test จริง · mTLS ระหว่าง services · Vault/secret-manager

## Definition of Done
1. NATS authz ขึ้นจริงบน local stack (gated test ผ่าน: authorized publish ok ·
   unauthorized reject) · `cargo test --workspace` เขียว · compose config ผ่าน
2. `cargo audit` job เขียวบน GitHub Actions (หรือแดงพร้อม fix/justified-ignore)
3. Cargo.lock committed + build reproducible (CI เขียวด้วย lock)
4. Docs 2 ไฟล์ครบ ใช้ได้จริง (คำสั่ง copy-paste ได้)
5. `PROGRESS.md` tick security deepening + log row
6. own PR off main — ไม่ merge เอง

## Review gate
2 agents (security + architecture) — จุดเพ่ง: ACL matrix least-privilege จริง ·
ไม่มี creds จริงหลุดเข้า repo · rollout ไม่ทำ staging down ถาวร · Cargo.lock
ไม่ดึง version แปลก
