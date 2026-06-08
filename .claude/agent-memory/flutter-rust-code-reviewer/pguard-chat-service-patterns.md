---
name: pguard-chat-service-patterns
description: Chat service architecture, IDOR gates, WS auth rules, outbox design, SQL conventions
metadata:
  type: project
---

## Service: chat (services/chat)

**Port:** 3010. Schema: `chat`. Branch: feat/chat-service.

### Auth model
- REST: `AuthUser` extractor (Bearer header or `access_token` cookie). All client routes gated.
- WS (`/ws/chat`): `AuthUser` runs before upgrade → token-in-URL => 401.
- Internal (`/internal/conversations/by-request/{id}/status`): `ServiceCaller` (service-JWT).

### IDOR pattern
- `list_messages`, `mark_read`, `upload_attachment`: `require_participant()` (primary pool) then action.
- `get_attachment`: fetches row first (404 if absent), then participant check (403). This leaks existence to non-participants.
- `create_conversation`: caller must be in `participants[]` or admin.
- `send_message` (repo): participant gate + sender_role derivation inside the tx (AUTHORITATIVE from chat.participants.user_role, never from client frame).
- Admin role bypasses participant gates everywhere.

### WS session (api/ws.rs)
- `authorized` HashSet prefetched from DB; grows on successful send.
- Outbound broadcast suppresses sender echo by `sender_id`.
- Room gate: `!is_admin && !authorized.contains(&out.conversation_id)`.
- Re-auth tick: 60s interval; if `token` is `None` (edge case where `token_from_headers` returned None but `AuthUser` still passed), re-auth is silently skipped.
- Cross-instance fan-out via Redis `psubscribe chat:*`.

### Outbox
- `send_message` tx order: lock conversation (FOR UPDATE) → check participants → check writable → INSERT message → INSERT outbox row → commit.
- Outbox relay (`events/run_relay`): connects NATS, polls every 2s, publish + mark_published (at-least-once; consumers dedupe on event_id).
- Poison message: malformed JSON in outbox row causes relay to reconnect indefinitely.

### SQL patterns
- `format!` in `list_messages` and `send_message` only interpolate `MESSAGE_COLUMNS` constant (no user input). Safe.
- `LIST_CONVERSATIONS_SQL`: single query, LATERALs for counterpart+last-msg, correlated subquery for unread (IS DISTINCT FROM). No pagination (consistent with OpenAPI contract).
- `message_type` stored as Postgres enum `chat.message_type`, read back as `::text`. Binds with `$n::chat.message_type` cast in INSERTs.

### Key divergences from spec/iron rules
- `get_attachment` leaks attachment existence (404 before IDOR check) — medium info-disclosure.
- `token` in WS session can be `None` causing silent re-auth skip if the header/cookie extraction fails after `AuthUser` succeeded.
- Upload handler buffers entire file into memory before size/magic-byte checks (full allocation before the domain validation gate).
- `data.len() as i32` cast for file_size: safe given 210 MB body cap < i32::MAX, but unchecked.
- `GET /conversations` has no pagination (no LIMIT/OFFSET in query or OpenAPI).

### Contract alignment
- `OutgoingChatMessage.message_type`: `String` in Rust (text cast from DB), enum `[text,image,video,system]` in OpenAPI/AsyncAPI. Wire values always valid.
- `sender_role`: `Option<String>` in both Rust and contracts. Correct.
- AsyncAPI envelope: `traceparent` nullable with `skip_serializing_if`. Contract says nullable. Aligned.
- Error envelope: `{ error: { code, message } }` — consistent with `shared::error::AppError` mapping.
