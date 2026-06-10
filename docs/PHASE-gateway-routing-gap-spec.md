# PHASE spec — Gateway routing gap (chat · presence · rating + WS proxy)

> **Slice:** ปิด gap ที่ api-gateway ไม่ route `chat / presence / rating` (REST) และ
> `/v1/ws/{chat,track,call}` (WebSocket) → feature เหล่านี้ **404 ที่ edge บน staging**
> ทั้งที่ backend service พร้อมและรันอยู่แล้ว
> **Worktree:** `feat/gateway-routing-gap` off `main` (หลัง `d6cd046`)
> **ห้ามแตะ `../guard-dispatch/`** (v1 reference, read-only)

---

## Why now

Staging LIVE ที่ `pguard.innoveraappcenter.com` แล้ว แต่ nginx ส่งทุก `/v1/*` เข้า
api-gateway ตัวเดียว (single ingress, by design) — อะไรที่ gateway ไม่รู้จัก = 404.
ปิด slice นี้ = staging ใช้ครบทุก feature (chat, live GPS map ผ่าน edge, calling
signaling, reviews) โดย mobile/web ไม่ต้อง bypass.

Breadcrumbs ที่มีอยู่แล้วใน repo:
- `services/api-gateway/src/domain/routing.rs:125-128` — comment ระบุ `/ws/call`
  upgrade ไม่อยู่ใน rules เพราะ "generic WS proxying through the gateway is a
  separate platform gap"
- `docs/STAGING-SETUP.md` known gaps — "gateway ยังไม่ route chat/presence/calling/rating"
- e2e: `apps/web-admin/next.config.ts` env-gated rewrites (`PGUARD_RATING_URL`/
  `PGUARD_PRESENCE_URL`) ที่ใส่ไว้เพื่อข้าม gap นี้
- perf harness: k6 chat/presence/rating ยิงตรง in-network เพราะ gateway ไม่ route

---

## สถานะปัจจุบัน (อ่านก่อนเขียนโค้ด)

### Gateway (services/api-gateway)
- `src/domain/routing.rs` — `enum Upstream` ปัจจุบัน 7 ตัว: Identity, Otp, Profile,
  Booking, Payment, Notification, Calling. `RULES: &[Rule]` เป็น **plain longest-prefix
  match** (`prefix` → `upstream` + `tier`), strip `/v1` ก่อน match.
- `src/state.rs` — ตาราง env URL ต่อ upstream (`IDENTITY_URL` … `CALLING_URL`,
  default `http://localhost:<port>`)
- `src/ws.rs` — **WS เดียวที่มีคือ bespoke hub** `GET /v1/ws/bookings/{id}`
  (NATS-subscribe ในตัว gateway, Bearer-on-upgrade, participant-gated) —
  **ไม่ใช่ proxy**; slice นี้ต้องเพิ่ม WS *proxy* จริงตัวแรก
- Tiers: `Tier::Auth` (5 r/s) · `Tier::Otp` (10 r/min) · `Tier::Api` (30 r/s);
  JWT validate ที่ edge (jti + trv + CSRF) ก่อน proxy; `/internal/` blocked ทุกกรณี
  (รวม `%2f` encoded separator) — กลไกพวกนี้**ต้อง apply กับ route ใหม่ทั้งหมดอัตโนมัติ**
- Tests: routing unit tests ใน `routing.rs` (~26) + handler integration + WS e2e
  (gated Redis/NATS) — ตามแพตเทิร์นเดิม

### Backend ที่ต้อง expose ผ่าน gateway (ports จาก compose.prod)

| Service | Port | REST routes (post-strip) | WS |
|---|---|---|---|
| chat | 3010 | `/conversations`, `/conversations/{id}/...`, `/attachments/{id}` | `/ws/chat` |
| presence | 3009 | `/locations`, `/guards/{id}/location`, `/guards/{id}/history` | `/ws/track` |
| rating | 3007 | `/assignments/{id}/review`, `/guards/{id}/ratings`, `/admin/reviews`, `/admin/reviews/{id}/visibility` | — |
| calling | 3008 | (routed แล้ว: `/calls`) | `/ws/call` |

ทุก WS backend เป็น **Bearer-on-upgrade** (ไม่มี token ใน URL) อยู่แล้ว.
ทุก service มี `/internal/*` (service-JWT) ที่**ห้าม**หลุดผ่าน edge — gateway block อยู่แล้ว
แต่ tests ต้องพิสูจน์ซ้ำกับ upstream ใหม่.

### ⚠️ Prefix collision — ตัวออกแบบหลักของ slice นี้

`/guards/{id}/ratings` → **rating** แต่ `/guards/{id}/location` + `/guards/{id}/history`
→ **presence**. plain prefix `/guards/` แยกไม่ได้.

**ทางที่แนะนำ (เลือก+justify ได้):** ขยาย `Rule` ให้รองรับ suffix/segment-pattern
(เช่น `prefix` + optional `suffix`: `/guards/` + `/ratings` → Rating;
`/guards/` + `/location`·`/history` → Presence) โดย**คง longest-prefix semantics
เดิมของ rule อื่นทุกตัว** (unit tests เดิม 26 ตัวต้องผ่านโดยไม่แก้ expectation).
ห้าม regex runtime แพง ๆ ใน hot path — segment match ธรรมดาพอ.

---

## Scope of work

### A. REST routing — 3 upstreams ใหม่
1. `enum Upstream` + `Rating`, `Presence`, `Chat` (+ `as_str`, state URL table,
   `all()` list, OTel attribute เดิมตามแพตเทิร์น)
2. Env: `RATING_URL` (default `http://localhost:3007`) · `PRESENCE_URL` (`:3009`) ·
   `CHAT_URL` (`:3010`)
3. Rules (ทั้งหมด `Tier::Api`; admin authz เป็นหน้าที่ service ปลายทาง — แพตเทิร์น
   เดียวกับ `/admin/guard-profiles` ที่ผ่าน Profile อยู่แล้ว):
   - `/conversations` → Chat · `/attachments` → Chat
   - `/locations` → Presence
   - `/guards/…/location`, `/guards/…/history` → Presence (ผ่านกลไก collision ข้อ ⚠️)
   - `/guards/…/ratings` → Rating
   - `/assignments/…/review` → Rating (ระวัง: ไม่มี rule `/assignments` อยู่เดิม —
     เช็คว่า booking ไม่ได้ใช้ prefix นี้ที่ gateway แล้วชนกัน)
   - `/admin/reviews` → Rating
4. compose.prod: เพิ่ม 3 env ใน api-gateway service (ชี้ DNS ภายใน เช่น
   `http://rating:3007`) — `RATING_URL` มีอยู่แล้วที่ **booking** (line ~417) อย่าสับสน;
   ของ slice นี้คือเพิ่มให้ **api-gateway**

### B. WebSocket proxy — `/v1/ws/{chat,track,call}`
1. Generic WS proxy ตัวแรกของ gateway: upgrade ที่ edge → เปิด WS client ไป
   backend (`/ws/chat`·`/ws/track`·`/ws/call`) → relay frames สองทางจนฝั่งใดปิด
   (รวม Close frame propagation + backpressure ตาม axum/tokio-tungstenite ปกติ)
2. **Auth ที่ edge ก่อน upgrade** (Bearer validate เหมือน REST: jti + trv) แล้ว
   **forward `Authorization` header เดิม** ไปกับ upgrade request ฝั่ง backend —
   backend validate ซ้ำเอง (defense-in-depth, แพตเทิร์นเดียวกับ `/ws/bookings`)
3. Rate-limit: ใช้แนวเดียวกับ `ws.rs` เดิม (per-IP connection limit) — nginx มี
   ws zone ชั้นนอกอยู่แล้วแต่ gateway ต้องไม่พึ่ง nginx
4. mapping: `/v1/ws/chat` → Chat `/ws/chat` · `/v1/ws/track` → Presence `/ws/track` ·
   `/v1/ws/call` → Calling `/ws/call` (Calling upstream มีอยู่แล้ว)
5. **อย่าแตะ** bespoke `/v1/ws/bookings/{id}` hub — คงพฤติกรรมเดิม 100%

### C. Cleanup ที่ปลดล็อกได้ (ทำใน slice นี้ ถ้า diff ไม่บาน)
- `docs/STAGING-SETUP.md` — ลบ/อัปเดต known-gap ข้อ gateway routing
- comment breadcrumb ใน `routing.rs:125-128` — อัปเดตให้ตรงความจริงใหม่
- **ไม่ต้อง**ถอด e2e env-gated rewrites ใน web-admin (`next.config.ts`) ใน slice นี้ —
  จดเป็น follow-up (e2e suite ต้อง re-verify แยก ไม่ผูก PR นี้)

### Out of scope
- mobile/web client เปลี่ยน URL (client ชี้ gateway อยู่แล้ว — แค่เลิก 404)
- mediasoup SFU media-plane · NATS subject-ACL · payment

---

## Hard rules (จาก CLAUDE.md — ย้ำ)
- Axum 0.8 `/{id}` syntax · ไม่มี `.unwrap()`/`.expect()` ใน request path
- domain/ pure (กลไก routing match ใหม่ = unit-testable ไม่มี I/O)
- `cargo fmt` + `cargo clippy --workspace --all-targets -D warnings` clean
- ห้าม copy v1 code; อ้าง path v1 ได้ถ้า audit แพตเทิร์น

## Definition of Done
1. Routing unit tests เดิมผ่าน **โดยไม่แก้ expectation** + tests ใหม่ครอบ:
   ทุก rule ใหม่ (รวม subpaths) · collision `/guards/{id}/{ratings,location,history}`
   แยกถูก · `/internal/*` ของ rating/presence/chat โดน block ที่ edge ·
   unauth WS upgrade = 401 ก่อนถึง backend
2. WS proxy integration test (gated แบบ ws e2e เดิม): echo/relay จริงผ่าน gateway
   อย่างน้อย 1 เส้น (chat หรือ track) + close propagation
3. `cargo test --workspace` เขียว · fmt/clippy clean
4. compose: `docker compose -f docker-compose.prod.yml config` ผ่าน (dummy secrets)
   และเห็น 3 env ใหม่ resolve
5. `PROGRESS.md`: tick + Completed-log row (date · task · what · files · verify)
6. own PR off main — **ไม่ merge เอง** (wei/Cowork audit + merge)

## Review gate
Workflow 2 agents ขั้นต่ำ: code-reviewer + architecture-guardian (จุดเพ่ง: routing
collision mechanism ไม่ทำ longest-prefix เดิมพัง · WS proxy ไม่มี auth bypass ·
`/internal` ยังถึง edge ไม่ได้ผ่าน upstream ใหม่) → fold blockers ก่อนปิด
