import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/chat_controller.dart';
import 'package:pguard_mobile/core/models/chat.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

Map<String, dynamic> msgJson(
  String id, {
  String conversation = 'cv1',
  String role = 'guard',
  String content = 'hi',
  String type = 'text',
  String at = '2026-06-05T10:00:00Z',
}) =>
    {
      'id': id,
      'conversation_id': conversation,
      'sender_id': 'u_$role',
      'sender_role': role,
      'content': content,
      'message_type': type,
      'created_at': at,
    };

ChatMessage incoming(String id,
        {String conversation = 'cv1', String role = 'customer'}) =>
    ChatMessage(
      id: id,
      conversationId: conversation,
      senderId: 'u_$role',
      senderRole: role,
      type: ChatMessageType.text,
      createdAt: DateTime.utc(2026),
    );

void main() {
  // Build a container wired to a fake api + fake chat feed; returns both for inspection.
  ({ProviderContainer c, FakeChatFeed feed, FakeApi api}) make({
    required List<Map<String, dynamic>> history,
  }) {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/conversations/cv1/messages');
        return history;
      },
      onPut: (_, __) async => {'success': true},
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      chatFeedBuilderProvider.overrideWithValue((tokenProvider) => feed),
    ]);
    addTearDown(c.dispose);
    return (c: c, feed: feed, api: api);
  }

  Future<List<ChatMessage>> load(ProviderContainer c) {
    // Keep the provider alive across emits.
    final sub =
        c.listen(chatControllerProvider('cv1', ChatRole.guard), (_, __) {});
    addTearDown(sub.close);
    return c.read(chatControllerProvider('cv1', ChatRole.guard).future);
  }

  test('history loads newest-first → rendered oldest-first; connects the feed',
      () async {
    final t = make(history: [
      msgJson('m2', at: '2026-06-05T10:02:00Z'),
      msgJson('m1', at: '2026-06-05T10:01:00Z'),
    ]);
    final list = await load(t.c);
    expect(list.map((m) => m.id).toList(), ['m1', 'm2'],
        reason: 'reversed to oldest-first for natural append + autoscroll');
    expect(t.feed.connected, isTrue);
    expect(t.api.getCount, 1,
        reason: 'one history fetch — messages are push, not polled');
  });

  test('marks the conversation read for the acting role on open', () async {
    final t = make(history: const []);
    await load(t.c);
    await Future<void>.delayed(Duration.zero); // let the best-effort PUT run
    expect(t.api.calls, contains('PUT /conversations/cv1/read?role=guard'));
  });

  test('incoming pushes append, deduped by id; foreign conversations ignored',
      () async {
    final t = make(history: [msgJson('m1')]);
    await load(t.c);

    t.feed.emit(incoming('m2'));
    await Future<void>.delayed(Duration.zero);
    expect(
        t.c
            .read(chatControllerProvider('cv1', ChatRole.guard))
            .value!
            .map((m) => m.id),
        ['m1', 'm2']);

    // Duplicate id (server echo / history overlap) is admitted once.
    t.feed.emit(incoming('m2'));
    await Future<void>.delayed(Duration.zero);
    expect(
        t.c.read(chatControllerProvider('cv1', ChatRole.guard)).value!.length,
        2,
        reason: 'dedupe by message id');

    // A frame for ANOTHER conversation must be ignored (one socket multiplexes all).
    t.feed.emit(incoming('m3', conversation: 'cvOTHER'));
    await Future<void>.delayed(Duration.zero);
    expect(
        t.c.read(chatControllerProvider('cv1', ChatRole.guard)).value!.length,
        2,
        reason: 'filtered by conversation id');
  });

  test('send pushes the right frame; the echo appends (deduped by id)',
      () async {
    final t = make(history: const []);
    await load(t.c);
    final ctrl =
        t.c.read(chatControllerProvider('cv1', ChatRole.guard).notifier);

    ctrl.send('  hello there  ');
    expect(t.feed.sent, hasLength(1));
    expect(t.feed.sent.single, {
      'conversation_id': 'cv1',
      'content': 'hello there', // trimmed
      'message_type': 'text',
      'sender_role': 'guard', // acting role, not sender id
    });

    // Blank sends are ignored.
    ctrl.send('   ');
    expect(t.feed.sent, hasLength(1));

    // The server echoes the persisted message back → it appends.
    t.feed.emit(incoming('server-id-1', role: 'guard'));
    await Future<void>.delayed(Duration.zero);
    final list = t.c.read(chatControllerProvider('cv1', ChatRole.guard)).value!;
    expect(list.single.id, 'server-id-1');
  });

  test('sendAttachment sends an image/video frame carrying the attachment id',
      () async {
    final t = make(history: const []);
    await load(t.c);
    final ctrl =
        t.c.read(chatControllerProvider('cv1', ChatRole.guard).notifier);

    ctrl.sendAttachment(const Attachment(
        id: 'att1', chatId: 'cv1', fileUrl: 'u', mimeType: 'image/jpeg'));
    expect(t.feed.sent.single, {
      'conversation_id': 'cv1',
      'content': 'att1',
      'message_type': 'image',
      'sender_role': 'guard',
    });
  });

  test('disposing the provider closes the WebSocket feed', () async {
    final t = make(history: const []);
    final sub =
        t.c.listen(chatControllerProvider('cv1', ChatRole.guard), (_, __) {});
    await t.c.read(chatControllerProvider('cv1', ChatRole.guard).future);
    sub.close();
    t.c.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(t.feed.closed, isTrue);
  });

  // ---- The SELF-VERIFIED read-only signal (chatServerClosedProvider) ----

  Map<String, dynamic> convJson(String id, {String? status}) => {
        'id': id,
        'request_id': 'r_$id',
        'created_at': '2026-06-05T10:00:00Z',
        'unread_count': 0,
        'request_status': status,
      };

  // Container whose api answers BOTH the message history and the conversations list (the
  // self-verify resolution reuses the chat-list fetch — no new endpoint).
  ({ProviderContainer c, FakeChatFeed feed}) makeWithList({
    required List<Map<String, dynamic>> conversations,
  }) {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (path, _) async =>
          path == '/conversations' ? conversations : <Map<String, dynamic>>[],
      onPut: (_, __) async => {'success': true},
    );
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
      chatFeedBuilderProvider.overrideWithValue((tokenProvider) => feed),
    ]);
    addTearDown(c.dispose);
    return (c: c, feed: feed);
  }

  test(
      'chatServerClosedProvider resolves the conversation status from the list '
      '(completed → closed, active → open, unknown → open)', () async {
    final t = makeWithList(conversations: [
      convJson('cv1', status: 'completed'),
      convJson('cv2', status: 'accepted'),
    ]);
    expect(
        await t.c
            .read(chatServerClosedProvider('cv1', ChatRole.customer).future),
        isTrue,
        reason: 'a completed booking closes the conversation');
    expect(
        await t.c
            .read(chatServerClosedProvider('cv2', ChatRole.customer).future),
        isFalse);
    expect(
        await t.c
            .read(chatServerClosedProvider('cvX', ChatRole.customer).future),
        isFalse,
        reason: 'unknown conversation → fall back to the navigation flag');
  });

  test(
      'a read_only send-rejection frame flips chatServerClosedProvider and '
      'surfaces on sendErrors', () async {
    final t = makeWithList(conversations: [
      convJson('cv1', status: 'accepted'), // list still says writable (stale)
    ]);
    final sub =
        t.c.listen(chatControllerProvider('cv1', ChatRole.guard), (_, __) {});
    addTearDown(sub.close);
    final closedSub =
        t.c.listen(chatServerClosedProvider('cv1', ChatRole.guard), (_, __) {});
    addTearDown(closedSub.close);
    await t.c.read(chatControllerProvider('cv1', ChatRole.guard).future);
    expect(
        await t.c.read(chatServerClosedProvider('cv1', ChatRole.guard).future),
        isFalse);

    final received = <ChatWsError>[];
    final errSub = t.c
        .read(chatControllerProvider('cv1', ChatRole.guard).notifier)
        .sendErrors
        .listen(received.add);
    addTearDown(errSub.cancel);

    // The booking completed while the thread was open → the server refuses the send.
    t.feed.emitError(const ChatWsError(
        code: 'read_only',
        message: 'Conversation is read-only (booking completed/cancelled)'));
    await Future<void>.delayed(Duration.zero);

    expect(
        t.c.read(chatServerClosedProvider('cv1', ChatRole.guard)).value, isTrue,
        reason: 'the rejection latches the read-only signal immediately');
    expect(received.single.isReadOnly, isTrue,
        reason: 'the rejection reaches the screen (snackbar) too');
  });

  test('a code-less error frame surfaces but does NOT lock the conversation',
      () async {
    final t =
        makeWithList(conversations: [convJson('cv1', status: 'accepted')]);
    final sub =
        t.c.listen(chatControllerProvider('cv1', ChatRole.guard), (_, __) {});
    addTearDown(sub.close);
    await t.c.read(chatControllerProvider('cv1', ChatRole.guard).future);

    final received = <ChatWsError>[];
    final errSub = t.c
        .read(chatControllerProvider('cv1', ChatRole.guard).notifier)
        .sendErrors
        .listen(received.add);
    addTearDown(errSub.cancel);

    t.feed.emitError(
        const ChatWsError(message: 'Not a participant of this conversation'));
    await Future<void>.delayed(Duration.zero);

    expect(received.single.isReadOnly, isFalse);
    expect(
        await t.c.read(chatServerClosedProvider('cv1', ChatRole.guard).future),
        isFalse,
        reason: 'only read_only closes the composer; other errors just toast');
  });
}
