# PHASE spec — Mobile presence + chat UI (ปิดงานค้าง Phase 2)

> **Slice:** (1) **customer live-map** ดูตำแหน่ง guard ของ booking ตัวเอง (presence UI
> ที่ยังไม่มีเลย) (2) **chat UI ให้จบ** — ส่วน controller/socket/tests มีแล้ว เหลือ
> entry points + attachments + ช่องว่างที่ audit เจอ
> **Worktree:** `feat/mobile-presence-chat-ui` off `main` (`d6cd046` ขึ้นไป)
> **แตะเฉพาะ `apps/mobile/`** — ห้ามแตะ services/* และ gateway (มี 2 slice ขนานอยู่)
> **ห้ามแตะ `../guard-dispatch/`** (read-only)

---

## สถานะจริง (audit แล้ว — เริ่มจาก verify ก่อนเขียน)

### มีอยู่แล้ว (ห้าม reinvent)
- WS infra: `lib/core/network/sockets/` — `ReconnectingWebSocket` (Bearer-on-upgrade,
  one-shot backoff timer ไม่ใช่ Timer.periodic) + typed wrappers ครบ:
  `chat_socket.dart` (`/v1/ws/chat`) · `presence_socket.dart` (`/v1/ws/track`)
- Chat: `ChatController` (history + dedupe `_seen` + alignment by `senderRole` +
  read-only จาก booking status) · `ChatListController` · `ChatLauncher` ·
  tests 6 ไฟล์ (controller + widget) ผ่านอยู่
- Presence guard-side: `TrackingController` + `OnlineCard` (GPS uplink เสร็จ)
- Reference chain ให้ copy: `booking_status_socket.dart` →
  `booking_status_controller.dart` → `live_status_screen.dart`
- Fakes: `test/support/fakes.dart` (FakeChatFeed, FakePresenceFeed, …)

### ยังไม่มี
- **Customer live-map**: จอดูตำแหน่ง guard แบบสด — ไม่มีเลย (มีแค่ map-picker
  ตอนเลือกพิกัด booking — reuse map lib ตัวเดียวกับที่ picker ใช้ ห้ามเพิ่ม lib ใหม่
  ถ้าของเดิมพอ)
- Chat: entry points จากจอ booking/active-job · attachment picker
  (`POST /attachments` + presigned download ตาม `contracts/openapi/chat.yaml`)
- **ขั้นแรกของงาน: audit ว่า `ChatScreen`/`ChatListScreen` widget มีจริงครบไหม**
  (tests มีแต่ implementation อาจยังไม่ครบ) — รายงานสิ่งที่เจอใน PR description
  แล้วเติมเฉพาะที่ขาด

## Scope of work

### A. Customer live-map (ของใหม่หลักของ slice)
1. **Data source:** snapshot `GET /v1/guards/{guardId}/location` (contract
   `contracts/openapi/presence.yaml`) — หมายเหตุ: gateway เพิ่ง route presence ใน slice
   ขนาน (`feat/gateway-routing-gap`) — **พัฒนา+test ด้วย fake feed ได้เลย ไม่ต้องรอ**
   แต่จด dependency ไว้ใน PR ว่า staging ใช้ได้หลัง gateway slice merge
2. **Live update:** ทางเลือก (เลือก+justify):
   (ก) poll snapshot — **ห้าม** (กติกา no Timer.periodic polling)
   (ข) ใช้ WS booking-status events (`guard_en_route`/`arrived`) + snapshot refresh
   ตอน event มา — ขั้นต่ำที่รับได้
   (ค) ถ้า contract/asyncapi มี location stream ฝั่ง read — ใช้อันนั้น
   **เช็ค contract จริงก่อนตัดสิน** อย่าสมมุติ
3. Controller ใหม่ `guard_location_controller.dart` ใน `core/controllers/`
   (pure, fake-injectable) — จอ map watch controller อย่างเดียว
4. UI: หน้า/section ใน live-status flow ของ customer (เข้าจาก `LiveStatusScreen`) —
   marker guard + ตำแหน่ง booking + สถานะ (en-route/arrived) · `PGuardHeader` ·
   i18n TH/EN ครบ
5. Screen < 800 LOC · ไม่มี business logic ใน widget state

### B. Chat — ปิดให้จบ
1. Audit แล้วเติม widget ที่ขาด (list + bubbles + composer + read-only banner)
2. Entry points: ปุ่ม chat จากจอ booking ฝั่ง customer + active-job ฝั่ง guard
   (ผ่าน `ChatLauncher` เดิม)
3. Attachments: picker (มี `lib/core/media/` อยู่แล้ว — `ChatAttachmentService`,
   `DocumentPicker`, `PhotoCapture`) → wire upload ตาม chat.yaml → render รูป/ไฟล์
   ใน bubble (download ผ่าน presigned URL; ห้าม cache token ลง prefs)
4. unread badge ที่ entry points (จาก `ChatListController` เดิม)

### Out of scope
- check-in wiring (`PendingCheckInService` → จริง) — รอ booking backend slice merge
- จอ presence ฝั่ง guard (มีแล้ว) · push notification ของ chat

## Hard rules (ย้ำ)
- Riverpod 2.x `@riverpod` codegen เท่านั้น — ห้าม Provider/ChangeNotifier
- ห้าม `Timer.periodic` polling ทุกกรณี
- WS lifecycle ใน controller (`ref.onDispose` cleanup) ไม่ใช่ใน widget
- `FlutterSecureStorage` สำหรับของ sensitive · `PGuardHeader` ห้าม copy-paste header

## Definition of Done
1. `flutter analyze` clean · `flutter test` เขียวทั้ง suite (เดิม ~45 ไฟล์ + ใหม่)
2. Tests ใหม่: guard_location_controller (fake feed: snapshot + update + dispose
   cleanup) · live-map widget (marker render + status) · chat attachment flow
   (controller-level ด้วย fake) · entry-point navigation
3. ไม่มี dependency ใหม่ใน pubspec ถ้า lib เดิมพอ (ถ้าจำเป็นต้อง justify ใน PR)
4. i18n TH/EN parity ทุก string ใหม่
5. `PROGRESS.md` tick + Completed-log row (ระบุ dependency ต่อ gateway slice ชัดเจน)
6. own PR off main — ไม่ merge เอง

## Review gate
2 agents ขั้นต่ำ (code + architecture; จุดเพ่ง: no-polling invariant · controller
purity · ไม่แตะ services/* · ไม่มี god-screen) → fold blockers ก่อนปิด
