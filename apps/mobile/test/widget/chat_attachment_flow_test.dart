import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/media/chat_media_picker.dart';
import 'package:pguard_mobile/core/models/chat.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/chat/chat_screen.dart';

import '../support/fakes.dart';

/// Attachment ids are UUIDs per the chat contract — the resolver validates the shape before
/// building a request path (the id arrives in counterpart-controlled WS frame content).
const imgId = '7d444840-9dc0-11d1-b245-5ffdce74fad2';

const attachment = Attachment(
  id: imgId,
  chatId: 'cv1',
  fileUrl: 'http://media.test/chat/cv1/x.jpg?sig=abc',
  mimeType: 'image/jpeg',
);

Map<String, dynamic> imageMsgJson() => {
      'id': 'm1',
      'conversation_id': 'cv1',
      'sender_id': 'u_customer',
      'sender_role': 'customer',
      'content': imgId,
      'message_type': 'image',
      'created_at': '2026-06-05T10:00:00Z',
    };

Widget host(
  FakeApi api,
  FakeChatFeed feed, {
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
      child: const MaterialApp(
        home: ChatScreen(
          conversationId: 'cv1',
          acting: ChatRole.guard,
          readOnly: false,
        ),
      ),
    );

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets(
      'attach: source sheet → picked+uploaded attachment → image WS frame '
      'carrying the attachment id', (tester) async {
    final feed = FakeChatFeed();
    final service = FakeChatAttachmentService(attachment: attachment);
    final api = FakeApi(
      onGet: (_, __) async => <Map<String, dynamic>>[],
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed, attachments: service));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pumpAndSettle();
    expect(find.text('ถ่ายรูป'), findsOneWidget);
    expect(find.text('เลือกรูปจากคลัง'), findsOneWidget);
    expect(find.text('เลือกวิดีโอจากคลัง'), findsOneWidget);

    await tester.tap(find.text('เลือกรูปจากคลัง'));
    await tester.pumpAndSettle();

    expect(service.picks.single, ChatAttachmentSource.galleryPhoto);
    expect(feed.sent.single, {
      'conversation_id': 'cv1',
      'content': imgId,
      'message_type': 'image',
      'sender_role': 'guard',
    });

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('attach: cancelled picker sends nothing (silent)',
      (tester) async {
    final feed = FakeChatFeed();
    final service = FakeChatAttachmentService(attachment: null);
    final api = FakeApi(
      onGet: (_, __) async => <Map<String, dynamic>>[],
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed, attachments: service));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ถ่ายรูป'));
    await tester.pumpAndSettle();

    expect(service.picks.single, ChatAttachmentSource.cameraPhoto);
    expect(feed.sent, isEmpty);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('attach: a rejected upload surfaces the friendly error',
      (tester) async {
    final feed = FakeChatFeed();
    final service = FakeChatAttachmentService(
        error: const ApiException(
            message: 'ไฟล์ใหญ่เกินไป / File too large', statusCode: 400));
    final api = FakeApi(
      onGet: (_, __) async => <Map<String, dynamic>>[],
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed, attachments: service));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลือกวิดีโอจากคลัง'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ไฟล์ใหญ่เกินไป'), findsOneWidget);
    expect(feed.sent, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'an image message resolves its attachment id to a fresh presigned URL '
      'and renders the image inline', (tester) async {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/attachments/$imgId') {
          return {
            'id': imgId,
            'chat_id': 'cv1',
            'file_key': 'chat/cv1/x.jpg',
            'file_url': 'http://media.test/chat/cv1/x.jpg?sig=abc',
            'mime_type': 'image/jpeg',
            'created_at': '2026-06-05T10:00:00Z',
          };
        }
        return [imageMsgJson()];
      },
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed));
    await settle(tester);
    await settle(tester); // attachment resolution round-trip

    expect(api.calls, contains('GET /attachments/$imgId'),
        reason: 'presigned URL resolved on view, never persisted');
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.url, 'http://media.test/chat/cv1/x.jpg?sig=abc');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a video message renders a labelled chip without resolving the '
      'attachment (no inline player, no wasted GET)', (tester) async {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (path, _) async {
        if (path.startsWith('/attachments/')) {
          fail('video bubbles must not resolve attachments');
        }
        return [
          imageMsgJson()
            ..['id'] = 'm2'
            ..['content'] = imgId
            ..['message_type'] = 'video'
        ];
      },
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed));
    await settle(tester);
    await settle(tester);

    expect(find.text('วิดีโอ'), findsOneWidget);
    expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a non-UUID attachment id (counterpart-controlled content) is rejected '
      'client-side — error chip, no API call', (tester) async {
    final feed = FakeChatFeed();
    final api = FakeApi(
      onGet: (path, _) async {
        if (path.startsWith('/attachments/')) {
          fail('malformed ids must never reach the request path');
        }
        return [
          imageMsgJson()..['content'] = 'x/../../me/data-export',
        ];
      },
      onPut: (_, __) async => {'success': true},
    );

    await tester.pumpWidget(host(api, feed));
    await settle(tester);
    await settle(tester);

    expect(find.text('โหลดไฟล์แนบไม่สำเร็จ'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
