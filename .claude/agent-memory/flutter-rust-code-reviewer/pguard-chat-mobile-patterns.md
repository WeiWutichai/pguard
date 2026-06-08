---
name: pguard-chat-mobile-patterns
description: Chat UI slice architecture, hard rules, Riverpod controller patterns, WS lifecycle, API contract alignment for the mobile chat feature
metadata:
  type: project
---

## Chat UI slice (apps/mobile, feat/mobile-chat branch)

**Key files:**
- `lib/core/models/chat.dart` — ChatMessage/Conversation/Attachment/ParticipantInput, ChatRole, ChatReadOnly, isFromRole (PURE)
- `lib/core/network/sockets/chat_socket.dart` — ChatFeed interface + ChatSocket (wraps ReconnectingWebSocket)
- `lib/core/controllers/chat_controller.dart` — AsyncNotifier, history+WS lifecycle
- `lib/core/controllers/chat_list_controller.dart` — enriched list, acting role
- `lib/core/controllers/chat_launcher.dart` — find-or-create (POST is not idempotent)
- `lib/features/chat/chat_screen.dart`, `chat_list_screen.dart`
- `lib/features/chat/widgets/chat_entry_button.dart`, `chat_bubble.dart`, `conversation_tile.dart`
- `lib/core/media/media_host.dart` — presigned URL host rewrite (PURE)
- `lib/core/media/chat_attachment_service.dart` — abstract + UnavailableChatAttachmentService

## Hard rules (verified/unverified in code)

1. **conversation_id in frame, never URL** — correct: ChatSocket.sendMessage puts it in the map. No subscribe frame (server persists every frame).
2. **Alignment by sender_role, never sender_id** — correct: isFromRole compares senderRole string.
3. **Dedupe by message id** — correct: _seen Set<String> in ChatController.
4. **Acting role passed in by caller** — correct: never inferred.
5. **Read-only hides composer** — correct: ChatReadOnly.fromStatus('completed'|'cancelled').
6. **WS lifecycle in controller** — correct: ref.onDispose cancels sub + closes feed.
7. **No Timer.periodic** — correct.
8. **Reuse ReconnectingWebSocket** — correct.
9. **POST /conversations not idempotent → find-first** — correct: ChatLauncher.resolveConversationId.

## WS send frame shape (production ChatSocket)
```dart
{
  'conversation_id': conversationId,
  if (content != null) 'content': content,  // CONDITIONAL — key omitted when null
  'message_type': type.wire,
  'sender_role': senderRole.wire,
}
```
AsyncAPI IncomingChatMessage schema: `conversation_id` required, `content`/`message_type`/`sender_role` optional with defaults.

## mark-read endpoint
`PUT /conversations/{id}/read?role={acting.wire}` — BUT the server ignores `?role=` for non-admin users (uses JWT role). Deliberate anti-spoofing. Documents in api/mod.rs:34.

## Known review findings (2026-06-07)

### Blocking
1. `_disposed` flag never reset to `false` at top of `build()` in ChatController — if provider is rebuilt (invalidateSelf), _onIncoming silently drops all frames. Fix: add `_disposed = false;` at start of build().
2. `FakeChatFeed.sendMessage` always includes `'content': content` (even null), diverging from production ChatSocket which conditionally omits the key. Tests pass for wrong reason.
3. `await feed.connect()` inside build() body risks state mutation before build() returns — if a frame arrives during the async connect, `_onIncoming` calls `state = AsyncData(...)` mid-build, triggering a rebuild loop. Fix: fire-and-forget `feed.connect()`.

### Major
- `counterpartName` not passed to ChatEntryButton in LiveStatusScreen or ActiveJobScreen — new conversations will have null participant display_name.

## API contract alignment
- Conversation list: `GET /v1/conversations?role=` → data array of EnrichedConversation — matched.
- Message history: `GET /v1/conversations/{id}/messages` → data array, newest-first; client reverses — matched.
- Mark read: `PUT /v1/conversations/{id}/read?role=` — matched (server ignores ?role for non-admin but that's OK).
- WS: `/ws/chat` (no conversation_id in URL), Bearer-on-upgrade — matched.
- Error envelope: `{ error: { code, message } }` (shared AppError mapping).
- Success envelope: `{ success, data }` — `ApiClient._unwrap()` extracts `data`.

## chatFeedBuilderProvider pattern
```dart
typedef ChatFeedBuilder = ChatFeed Function(Future<String?> Function() tokenProvider);

@Riverpod(keepAlive: true)
ChatFeedBuilder chatFeedBuilder(ChatFeedBuilderRef ref) =>
    (tokenProvider) => ChatSocket(tokenProvider: tokenProvider);
```
Tests override with: `chatFeedBuilderProvider.overrideWithValue((tokenProvider) => feed)`.
