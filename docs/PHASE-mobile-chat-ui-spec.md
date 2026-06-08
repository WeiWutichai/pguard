# mobile — chat UI (Flutter + Riverpod) — work spec

> For Claude Code (Terminal A). Build the chat screens against the **already-merged** chat
> backend (`contracts/openapi/chat.yaml` + `contracts/asyncapi/chat-ws.yaml`). Reuse the
> existing `ws_client` + Riverpod-codegen patterns from the booking/presence slices. **Contracts
> are source of truth — read them, don't assume v1 paths.** Branch off freshly synced main.
> Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 03653b8 (backend v2 complete)
git worktree add ../pguard-mobile-chat -b feat/mobile-chat-ui main
cd ../pguard-mobile-chat
```

## What exists to reuse (don't reinvent)
- `apps/mobile/lib/core/network/sockets/{ws_client.dart, backoff.dart}` — reconnecting WS, Bearer-on-upgrade, `send()` + `connectionChanges` (added in the guard-app slice).
- Riverpod `@riverpod` codegen controllers (see `notification_controller.dart`, `guard_jobs_controller.dart`), `api_client.dart` (Dio `/v1`, proactive refresh), `app_router.dart` (go_router codegen).
- The chat backend contract: `GET /conversations?role=`, `GET /conversations/{id}/messages`, `PUT /conversations/{id}/read?role=`, `POST /conversations`, `POST /attachments`, `GET /attachments/{id}`, WS `GET /ws/chat`.

## Scope

### A. Chat list screen
- `ChatListController` (AsyncNotifier) → `GET /v1/conversations?role={acting}` (N+1-free — one call). Render: counterpart name+avatar, last message, last-message time (locale-aware relative, reuse `relative_time.dart`), unread badge.
- **acting role** is passed in by the caller (guard dashboard → `guard`, customer/hirer → `customer`) — never inferred from user id. Pull-to-refresh; refresh on return from a chat.
- **Read-only conversations**: when `request_status` is `completed`/`cancelled`, mark the row read-only and pass that flag down to the chat screen.

### B. Chat screen (real-time)
- On open: `GET /v1/conversations/{id}/messages` (history, newest-first) + connect WS `/ws/chat` (Bearer-on-upgrade via `ws_client`) + `PUT /conversations/{id}/read?role=`.
- **conversation_id is sent as the FIRST message after the socket opens** (it is NOT in the URL — contract rule). 
- Incoming message frames → append; **dedupe by message id** (server echoes your own send back). 
- **Alignment by `sender_role == actingRole`** → right (me) / left (them) — **never** `sender_id == myId` (same user can be guard in one convo, customer in another).
- Send: push `{ conversation_id, content, message_type, sender_role: actingRole }` over WS; clear input; autoscroll. Sent ticks (done / done-all for last in group).
- **Read-only mode** (`readOnly: true`): hide the composer + call button, show a locked banner ("งานสิ้นสุดแล้ว ไม่สามารถส่งข้อความได้" / "Job ended. Messaging is disabled.") — and the server already rejects writes, so this is UX only.
- WS lifecycle lives in the controller/`core/network/sockets`, **not** in widget state (CLAUDE.md). Dispose → disconnect.

### C. Attachments
- Pick image/video → `POST /v1/attachments` (multipart) → render inline; tap → fetch presigned `GET /attachments/{id}`. Respect the size limits the backend enforces (10MB image / 200MB video) — surface a friendly error if rejected.
- Apply `rewriteMediaHost` / the platform host-rewrite pattern if presigned URLs come back with an internal host (mirror what profile/avatar does).

### D. Entry points
- Guard `job_detail`/`active_job` + customer active-job/tracking screens get a chat button → open the conversation for that `request_id` (create-or-find via `POST /conversations` if needed, else navigate). Pass `actingRole` + `readOnly` (from request status).

## Layering / rules (CLAUDE.md mobile)
- Riverpod 2.x `@riverpod` codegen; pure logic (dedupe, alignment, unread, read-only decision) in controllers — widget-free + unit-tested. No `Timer.periodic` for messages (WS push). `PGuardHeader` for headers. No god-screens >800 LOC.

## Definition of Done
- `flutter analyze` ✅ clean · `flutter test` ✅ (new tests pass) · `build_runner` codegen ok (`*.g.dart` gitignored).
- **Controller unit tests** (no widgets): list load + unread; message dedupe-by-id; alignment by `sender_role`; read-only decision from `request_status`; send appends/echoes; WS disconnect on dispose.
- Widget tests: list (unread badge, empty), chat (alignment left/right, read-only banner hides composer).
- Reuses `ws_client` (no new bespoke socket); conversation_id sent after open (not URL); acting-role threaded through.
- Update `PROGRESS.md` (tick chat-mobile under Phase 2 + Completed-log row) · run the review agents (flutter-rust-code-reviewer + code-reviewer + architecture-guardian) · own PR off main · **don't merge**.

## Reference (read-only)
- v2 patterns: `apps/mobile/lib/features/notifications/*` (AsyncNotifier + optimistic), `core/network/sockets/*` (WS), `features/guard/*` (screens reaching WS). Contracts: `contracts/openapi/chat.yaml` + `contracts/asyncapi/chat-ws.yaml`.
- v1 UX to port (cite paths; adapt to Riverpod + v2 contract): `../guard-dispatch/frontend/mobile/lib/screens/{chat_list_screen,chat_screen}.dart` — role-aware list, alignment by sender_role, unread badge, read-only mode. **But** v2 sends conversation_id after WS open and uses `/v1` paths — follow the contract, not v1's `IOWebSocketChannel` URL shape.
