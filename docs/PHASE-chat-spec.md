# chat — messaging service (REST + WebSocket, N+1 fixed) — backend slice — work spec

> For Claude Code. The `chat` service is a **39-LOC stub** (health only) with an **empty
> migration dir**. Build the whole thing: schema, conversations/messages/read-receipts/
> attachments, the real-time WS, and the **N+1-free** `list_conversations`. **Mirror
> `services/calling/src/api/ws.rs` for the WS pattern** and reuse the profile/booking services
> for the S3 attachment + IDOR patterns. **Contracts first.** Branch off freshly synced main.
> Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # must be at 38e91e6 (Phase 5 complete + infra fix)
git worktree add ../pguard-chat -b feat/chat-service main
cd ../pguard-chat
```

## Scope

### A. Schema — new migrations under `contracts/db/migrations/chat/`
- `chat.conversations` (`id`, `request_id UUID` — links a booking, bare UUID no cross-svc FK, `created_at`).
- `chat.participants` (`conversation_id`, `user_id`, `user_role VARCHAR(20)`) — a user can be in a convo as guard **or** customer.
- `chat.messages` (`id`, `conversation_id`, `sender_id`, **`sender_role VARCHAR(20)`** — `'guard'`/`'customer'`, drives alignment, `content`, `message_type`, `created_at`). Index `(conversation_id, created_at DESC)`.
- `chat.read_receipts` (PK `(conversation_id, user_id, user_role)`, `last_read_message_id`, `read_at`) — **per-role** receipts (same user reading as guard vs customer tracked separately).
- `chat.attachments` (`id`, `chat_id`, `uploader_id`, `file_key`, `file_url`, `file_size`, `mime_type`, `created_at`).

### B. REST
- `POST /conversations` `{ request_id, participant_ids[] }` — create, link to booking request.
- `GET /conversations?role=guard|customer` — **the N+1 fix.** ONE query: JOIN through `booking`-derived participant data + `chat.messages` (last message) + unread count; return `participant_name`, `participant_avatar`, `last_message`, `last_message_at`, `unread_count`, `request_status`. **Name resolution uses the `acting_role` param** (guard sees customer name, customer sees guard name) — never `sender_id`. Cross-service names come via **API/event-derived data, NOT a cross-schema JOIN** (CLAUDE.md v2 Data rules — v1 JOINed auth/booking directly; v2 must not).
- `GET /conversations/{id}/messages?limit&offset` — newest-first, includes `sender_role`.
- `PUT /conversations/{id}/read?role=` — UPSERT read receipt with `user_role`.
- **Unread count** = messages where `sender_role IS DISTINCT FROM acting_role AND created_at > read_at`.
- `POST /attachments` (multipart) + `GET /attachments/{id}` (presigned). **Validate declared MIME AND magic bytes** (JPEG `FF D8 FF` · PNG `89 50 4E 47 0D 0A 1A 0A` · WEBP `RIFF…WEBP` · MP4 bytes4-7 `ftyp` · QuickTime `ftyp`+`qt  `). Size: 10MB image / 200MB video. Validate **size before magic bytes**. Signed URL TTL 1h; never expose bucket. `file_key = chat/{chat_id}/{uuid}.{ext}`.

### C. WebSocket — `GET /ws/chat`
- **Bearer-on-upgrade** (AuthUser before upgrade); token in URL query → 401. **conversation_id is NOT in the URL** — sent as a message after open (CLAUDE.md: no sensitive data in WS URL).
- Incoming `{ conversation_id, content, message_type, sender_role }` → persist → broadcast `{ id, conversation_id, sender_id, sender_role, content, message_type, created_at }`.
- **Redis pub/sub** for cross-instance broadcast (mirror calling's fan-out, but topic-per-conversation).
- **Message alignment is by `sender_role == acting_role`**, never `sender_id == userId` (same user can send as guard in one convo, customer in another).

### D. Authorization (IDOR — non-negotiable)
- `list_messages` / attachment upload+signed-url / mark-read: caller must be a **participant** of the conversation (admin bypasses). Use a participant check; **never** `_user: AuthUser` (ignored). 
- Read-only mode: when the linked `request_status` is `completed`/`cancelled`, the client disables send — but the **server must also reject** writes to a closed conversation (don't trust the client).

### E. Events (NATS)
- Emit `pguard.events.chat.message_sent` (topic const already in `packages/shared-events`: `CHAT_MESSAGE_SENT`) via the **transactional outbox** (atomic with the message INSERT) — notification consumes it. No direct INSERT into notification's schema.

### F. Contracts (write FIRST)
- `contracts/openapi/chat.yaml` — all REST + attachment shapes + authz notes.
- `contracts/asyncapi/chat-ws.yaml` — `/ws/chat` channel (incoming/outgoing message, Bearer-on-upgrade, conversation_id-after-open) + the `chat.message_sent` event.

## Layering (CLAUDE.md per-service)
`api/` (ws.rs + REST, thin) · `domain/` (unread-count math, alignment, magic-byte validators, read-only-state rule — pure, unit-testable) · `repo/` (sqlx; the single N+1-free conversations query lives here) · `events/` (outbox emit + Redis pub/sub) · `models.rs` · `state.rs`. Reuse `shared::{auth, config, error, service_jwt}`, the S3 helper pattern from `services/profile`, `observability`.

## Definition of Done
- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅.
- **Domain unit tests**: unread-count (`IS DISTINCT FROM` semantics), role-based alignment, every magic-byte validator (accept + reject + size-before-magic), read-only-state rule.
- `list_conversations` is **one** query (prove no N+1 — e.g. a repo test asserting a single round-trip / query log).
- WS: Bearer-only (query-token 401), conversation_id-after-open, participant gate on the wire, alignment by role.
- IDOR tests: non-participant → 403 on messages/attachments/mark-read; write to completed/cancelled convo rejected server-side.
- `message_sent` emitted via outbox (atomic) — test the outbox row is written in the same tx.
- Contracts committed (openapi + asyncapi) and match handlers.
- Update `PROGRESS.md` (tick chat + Completed-log row) · run the 3 review agents · own PR off main · **don't merge**.

## Reference (read-only)
- v2 WS + outbox pattern: `services/calling/src/{api/ws.rs, events/mod.rs, repo/mod.rs}`; S3 attachment pattern: `services/profile`.
- v1 logic to port (cite v1 paths): `../guard-dispatch/services/chat/` — `sender_role` alignment, unread `COUNT(... IS DISTINCT FROM ...)`, **N+1 fix** in `list_conversations`, read_receipts per-role PK, attachment magic-bytes + signed URL, `is_conversation_participant` IDOR. CLAUDE.md (guard-dispatch) "Chat Tables" + "File Upload" + "Authorization (IDOR)" are the rule list.
