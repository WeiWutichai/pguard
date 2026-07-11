import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/chat.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/chat/chat_screen.dart';

import '../support/fakes.dart';

// NOTE: `sender_id` is INTENTIONALLY the SAME for both senders here — alignment must be decided by
// `sender_role` vs the VIEWER's acting role, never by sender id (the regression this guards).
Map<String, dynamic> msgJson(String id, String role, String content) => {
      'id': id,
      'conversation_id': 'cv1',
      'sender_id': 'same-physical-user',
      'sender_role': role,
      'content': content,
      'message_type': 'text',
      'created_at': '2026-06-05T10:00:00Z',
    };

Widget host(
  FakeApi api,
  FakeChatFeed feed, {
  required bool readOnly,
  ChatRole acting = ChatRole.guard,
  FakeChatAttachmentService? attachments,
}) =>
    ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
        chatFeedBuilderProvider.overrideWithValue((tokenProvider) => feed),
        if (attachments != null)
          chatAttachmentServiceProvider.overrideWithValue(attachments),
      ],
      child: MaterialApp(
        home: ChatScreen(
          conversationId: 'cv1',
          acting: acting,
          readOnly: readOnly,
        ),
      ),
    );

/// The Align directly wrapping a bubble's text — its alignment is the bubble side.
Alignment sideOf(WidgetTester tester, String text) => tester
    .widget<Align>(
      find.ancestor(of: find.text(text), matching: find.byType(Align)).first,
    )
    .alignment as Alignment;

void main() {
  testWidgets('aligns own role right, counterpart left; composer is shown',
      (tester) async {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (_, __) async => [
        msgJson('m1', 'guard', 'from guard'),
        msgJson('m2', 'customer', 'from customer'),
      ],
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed, readOnly: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('from guard'), findsOneWidget);
    expect(find.text('from customer'), findsOneWidget);

    // Alignment is by sender_role vs acting (guard): own → right, counterpart → left.
    final mine = tester.widget<Align>(find
        .ancestor(of: find.text('from guard'), matching: find.byType(Align))
        .first);
    expect(mine.alignment, Alignment.centerRight);
    final theirs = tester.widget<Align>(find
        .ancestor(of: find.text('from customer'), matching: find.byType(Align))
        .first);
    expect(theirs.alignment, Alignment.centerLeft);

    // Writable conversation → composer present.
    expect(find.byType(TextField), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  // Bug #2 regression: the SAME two-sender thread must FLIP per viewer. A guard-sent message is
  // RIGHT for the guard viewer and LEFT for the customer viewer, and vice-versa — driven purely by
  // each entry point passing the VIEWER's own acting role to ChatScreen (guard screens → guard,
  // customer screens → customer). Both senders share one sender_id, so any sender-id-based
  // alignment would put a message on the SAME side in both views (the reported on-device bug).
  testWidgets(
      'same thread flips left/right per viewer role (guard view vs customer view)',
      (tester) async {
    List<Map<String, dynamic>> thread() => [
          msgJson('m1', 'guard', 'from guard'),
          msgJson('m2', 'customer', 'from customer'),
        ];

    // ----- GUARD viewer: guard RIGHT, customer LEFT -----
    final guardApi = FakeApi(
      onGet: (_, __) async => thread(),
      onPut: (_, __) async => {'success': true},
    );
    await tester.pumpWidget(host(guardApi, FakeChatFeed(),
        readOnly: false, acting: ChatRole.guard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(sideOf(tester, 'from guard'), Alignment.centerRight,
        reason: 'guard viewer: own (guard) message on the right');
    expect(sideOf(tester, 'from customer'), Alignment.centerLeft,
        reason: 'guard viewer: counterpart (customer) message on the left');

    await tester.pumpWidget(const SizedBox());

    // ----- CUSTOMER viewer: SAME thread, sides FLIPPED -----
    final customerApi = FakeApi(
      onGet: (_, __) async => thread(),
      onPut: (_, __) async => {'success': true},
    );
    await tester.pumpWidget(host(customerApi, FakeChatFeed(),
        readOnly: false, acting: ChatRole.customer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(sideOf(tester, 'from customer'), Alignment.centerRight,
        reason: 'customer viewer: own (customer) message on the right');
    expect(sideOf(tester, 'from guard'), Alignment.centerLeft,
        reason: 'customer viewer: counterpart (guard) message on the left');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read-only conversation hides the composer + shows locked banner',
      (tester) async {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (_, __) async => <Map<String, dynamic>>[],
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed, readOnly: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(TextField), findsNothing, reason: 'composer hidden');
    expect(find.textContaining('งานสิ้นสุดแล้ว'), findsOneWidget,
        reason: 'locked banner');

    await tester.pumpWidget(const SizedBox());
  });

  // The screen SELF-VERIFIES read-only: the push-notification entry hardcodes readOnly:false
  // (the payload has no booking status), so the screen must resolve the conversation's CURRENT
  // status from the server (the conversations list carries request_status) and lock itself.
  testWidgets(
      'opened with readOnly:false but the server says the booking completed → '
      'composer locked', (tester) async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/conversations') {
          return [
            {
              'id': 'cv1',
              'request_id': 'r1',
              'created_at': '2026-06-05T10:00:00Z',
              'unread_count': 0,
              'request_status': 'completed',
            }
          ];
        }
        return <Map<String, dynamic>>[]; // message history
      },
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, FakeChatFeed(), readOnly: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(TextField), findsNothing,
        reason: 'the SERVER status wins over the stale navigation flag');
    expect(find.text('งานสิ้นสุดแล้ว ไม่สามารถส่งข้อความได้'), findsOneWidget,
        reason: 'locked banner replaces the composer');
    expect(find.text('งานเสร็จสิ้นแล้ว'), findsOneWidget,
        reason: 'the header subtitle flips to job-completed too');

    await tester.pumpWidget(const SizedBox());
  });

  // A rejected WS send must not vanish silently: `code: read_only` shows the localized
  // job-ended line AND locks the composer reactively (the booking completed while typing).
  testWidgets(
      'read_only error frame → snackbar + composer swaps to the locked banner',
      (tester) async {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/conversations') {
          return [
            {
              'id': 'cv1',
              'request_id': 'r1',
              'created_at': '2026-06-05T10:00:00Z',
              'unread_count': 0,
              'request_status': 'accepted', // still writable at open time
            }
          ];
        }
        return <Map<String, dynamic>>[];
      },
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed, readOnly: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byType(TextField), findsOneWidget,
        reason: 'writable at open time');

    // The booking completes while the thread is open; the next send is refused on the wire.
    feed.emitError(const ChatWsError(
        code: 'read_only',
        message: 'Conversation is read-only (booking completed/cancelled)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('งานสิ้นสุดแล้ว — ส่งข้อความไม่ได้'), findsOneWidget,
        reason: 'the localized read-only snackbar (never the raw English)');
    expect(find.byType(TextField), findsNothing,
        reason: 'the composer locks reactively');
    expect(find.text('งานสิ้นสุดแล้ว ไม่สามารถส่งข้อความได้'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  // Backward compat: an error frame WITHOUT a code still surfaces (generic snackbar), and the
  // composer stays — only read_only locks it.
  testWidgets('code-less error frame → generic snackbar, composer stays',
      (tester) async {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/conversations') {
          return [
            {
              'id': 'cv1',
              'request_id': 'r1',
              'created_at': '2026-06-05T10:00:00Z',
              'unread_count': 0,
              'request_status': 'accepted',
            }
          ];
        }
        return <Map<String, dynamic>>[];
      },
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed, readOnly: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    feed.emitError(
        const ChatWsError(message: 'Not a participant of this conversation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Not a participant of this conversation'), findsOneWidget,
        reason: 'the client-safe server message surfaces as-is');
    expect(find.byType(TextField), findsOneWidget,
        reason: 'a non-read_only rejection never locks the composer');

    await tester.pumpWidget(const SizedBox());
  });

  // Bug #3: a booking can complete WHILE the thread is open (the read-only route flag is stale), so
  // an upload still fires and the chat service rejects it with 409. The screen must surface the
  // localized "job ended" line, NOT the generic transport "Network error" the bare 413/409 would
  // otherwise produce.
  testWidgets(
      'upload on a now-read-only conversation shows the read-only message, '
      'not a network error', (tester) async {
    final feed = FakeChatFeed();
    // The chat service returns 409 Conflict for a read-only upload (booking completed/cancelled).
    final service = FakeChatAttachmentService(
      error: const ApiException(
        message: 'Conversation is read-only (booking completed/cancelled)',
        statusCode: 409,
      ),
    );
    final api = FakeApi(
      onGet: (_, __) async => <Map<String, dynamic>>[],
      onPut: (_, __) async => {'success': true},
    );

    // readOnly:false → the composer (and attach button) is still shown (stale flag), so the upload
    // is attempted and the 409 path is exercised.
    await tester
        .pumpWidget(host(api, feed, readOnly: false, attachments: service));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลือกรูปจากคลัง'));
    await tester.pumpAndSettle();

    // The localized read-only line — NOT the server's English text, NOT "Network error".
    expect(find.text('งานสิ้นสุดแล้ว — ส่งข้อความไม่ได้'), findsOneWidget);
    expect(find.textContaining('Network error'), findsNothing);
    expect(find.textContaining('read-only'), findsNothing,
        reason: 'the raw English server message must not leak');
    expect(feed.sent, isEmpty, reason: 'nothing sent on a rejected upload');

    await tester.pumpWidget(const SizedBox());
  });
}
