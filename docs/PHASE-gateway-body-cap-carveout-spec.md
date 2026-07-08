# PHASE spec — Gateway body-cap carve-out (ปลดล็อก check-in photo + chat attachments)

> **Slice สุดท้ายของกลุ่ม A:** gateway buffer ทุก proxied body ที่ **1 MiB**
> (`services/api-gateway/src/proxy.rs:21 MAX_BODY_BYTES`) + nginx staging
> `client_max_body_size 2m` (`nginx.staging.conf:61`) → upload จริงโดน 413 ที่ edge:
> - `POST /v1/bookings/{id}/progress-reports` — check-in photo ≤10MB (merged แล้ว, PR #27)
> - `POST /v1/attachments` — chat attachment (เพิ่ง expose ผ่าน edge ใน PR #25)
>
> **Worktree:** `feat/gateway-body-cap-carveout` off `main` (`50a2085` ขึ้นไป)
> **ปลดล็อก:** mobile check-in wiring (slice ถัดไป) + chat attachment บน staging
> **ห้ามแตะ `../guard-dispatch/`** (read-only)

---

## สถานะปัจจุบัน (อ่านก่อน)

- `proxy.rs` — `to_bytes(body, MAX_BODY_BYTES)` buffer ทั้ง body ก่อน forward
  (DoS guard, const ตัวเดียวใช้ทุก route) · WS proxy reuse const นี้เป็น frame cap
  (`wsproxy.rs` — **อย่าให้ carve-out ไปขยาย frame cap ด้วย**)
- Routing: `domain/routing.rs` มี `Rule { prefix, suffix, upstream, tier }`
  (PR #25 เพิ่ม suffix segment-pattern แล้ว — กลไกนี้ match
  `/bookings/{id}/progress-reports` ได้เลย)
- ปลายทาง validate เองอยู่แล้ว: booking multipart cap ~10MB+framing
  (`booking/src/api/mod.rs:40`) + IDOR ก่อน buffer · chat `DefaultBodyLimit`
  (`chat/src/main.rs:138`) — gateway แค่ต้องเลิกเป็นคอขวด
- nginx staging: `client_max_body_size 2m` ระดับ server block

## Scope of work

### A. Per-route body cap ที่ gateway
1. ขยาย route decision ให้ตอบ **body cap ต่อ route** (แนะนำ: field ใหม่บน `Rule`
   เช่น `body_cap: BodyCap::{Default, Large}` → const `MAX_BODY_BYTES` 1 MiB /
   `LARGE_BODY_BYTES` **12 MiB**) — กลไกอยู่ใน `domain/` pure + unit-testable
2. Carve เฉพาะ 2 route (method-aware ถ้า structure เอื้อ — GET ไม่ควรได้ cap ใหญ่;
   ถ้า Rule ไม่รู้ method ให้ justify ว่า cap ใหญ่ทั้ง prefix ยอมรับได้เพราะ
   ปลายทาง validate ซ้ำ):
   - `/bookings/{wildcard}/progress-reports` → Booking (ใช้ suffix mechanism เดิม)
   - `/attachments` → Chat
3. `proxy.rs` ใช้ cap จาก decision แทน const ตรงๆ — **ทุก route อื่นต้องคง 1 MiB
   เป๊ะ** (test เดิม 413 ที่ 1 MiB+1 ต้องผ่านไม่แก้ expectation)
4. **ทางเลือก streaming** (ถ้าจะทำให้ดีกว่า buffer 12 MiB ต่อ request): forward
   body แบบ stream เฉพาะ carved routes โดยคง cap ด้วย limited-stream — เลือกได้
   แต่ต้อง justify + พิสูจน์ memory bound; ถ้า buffer ธรรมดาให้ note ว่า
   concurrent large uploads × 12 MiB = bounded โดย rate limit ชั้นนอก
5. WS frame cap (`wsproxy.rs`) **ไม่เปลี่ยน** — แตก const แยกถ้าจำเป็น

### B. nginx staging
- `nginx.staging.conf`: เพิ่ม location เฉพาะ (ใน server :443) สำหรับ 2 path นี้
  `client_max_body_size 12m` + proxy settings เดิมของ `/v1/` ทุกประการ
  (rate zone เดิม · WS plumbing ไม่เกี่ยว) — ระวัง nginx inheritance:
  directive ใน location ใหม่ต้องครบเท่าตัวแม่ (copy ชุด proxy_* มาให้ครบ)
- `nginx -t` ผ่านใน throwaway container (แพตเทิร์น verify เดิมของ staging slice)

### C. Docs
- `docs/STAGING-SETUP.md` — อัปเดต known-gap "gateway 1 MiB body cap" → closed
  (ระบุ carved routes + cap)
- `PROGRESS.md` — tick `[ ] Gateway body-cap carve-out` ในกลุ่ม A + log row

### Out of scope
- mobile check-in wiring (slice ถัดไปหลังอันนี้ merge)
- per-user upload quota / virus scan (จดเป็น follow-up ได้)

## Hard rules (ย้ำ)
- ไม่มี `.unwrap()`/`.expect()` ใน request path · domain pure
- `cargo fmt` + `clippy --workspace --all-targets -D warnings` clean

## Definition of Done
1. Unit tests: routing decision คืน cap ถูกต่อ route (carved 2 เส้น = Large,
   adversarial: `/bookings/x/progress-reportsx`, `/attachmentsx`, GET เดิม,
   `/v1/ws/*` = Default) · tests 413 เดิมผ่านไม่แก้ expectation
2. Integration/e2e (gated ตามแพตเทิร์นเดิม): POST 5 MiB ผ่าน carved route ถึง
   backend stub สำเร็จ · 13 MiB → 413 · route ปกติ 1 MiB+1 → 413 เดิม
3. `cargo test --workspace` เขียว · fmt/clippy clean · `nginx -t` ผ่าน
4. `PROGRESS.md` tick + log row
5. own PR off main — ไม่ merge เอง

## Review gate
2 agents (code + security; จุดเพ่ง: cap อื่นไม่ขยับ · WS frame cap ไม่ขยับ ·
memory bound ของ large uploads · nginx location inheritance ครบ) → fold blockers
