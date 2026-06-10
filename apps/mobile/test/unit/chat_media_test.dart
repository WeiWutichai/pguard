import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/media/chat_media_picker.dart';
import 'package:pguard_mobile/core/models/chat.dart';

Conversation conv(String id, String requestId, int unread) =>
    Conversation.fromJson({
      'id': id,
      'request_id': requestId,
      'created_at': '2026-06-10T00:00:00Z',
      'unread_count': unread,
    });

void main() {
  group('ChatMime', () {
    test('maps the contract-accepted extensions (case-insensitive)', () {
      expect(ChatMime.fromPath('/tmp/a.jpg'), 'image/jpeg');
      expect(ChatMime.fromPath('/tmp/a.JPEG'), 'image/jpeg');
      expect(ChatMime.fromPath('/tmp/a.png'), 'image/png');
      expect(ChatMime.fromPath('/tmp/a.webp'), 'image/webp');
      expect(ChatMime.fromPath('/tmp/a.mp4'), 'video/mp4');
      expect(ChatMime.fromPath('/tmp/a.MOV'), 'video/quicktime');
    });

    test('unknown/missing extension → null', () {
      expect(ChatMime.fromPath('/tmp/a.gif'), isNull);
      expect(ChatMime.fromPath('/tmp/noext'), isNull);
      expect(ChatMime.fromPath('/tmp/trailingdot.'), isNull);
    });

    test('isSupported accepts only the contract MIME set', () {
      expect(ChatMime.isSupported('image/jpeg'), isTrue);
      expect(ChatMime.isSupported('video/quicktime'), isTrue);
      expect(ChatMime.isSupported('image/gif'), isFalse);
      expect(ChatMime.isSupported(null), isFalse);
    });
  });

  group('unreadTotal', () {
    final conversations = [
      conv('c1', 'b1', 2),
      conv('c2', 'b2', 0),
      conv('c3', 'b3', 5),
    ];

    test('sums across all conversations', () {
      expect(unreadTotal(conversations), 7);
    });

    test('narrows to one booking via requestId', () {
      expect(unreadTotal(conversations, requestId: 'b3'), 5);
      expect(unreadTotal(conversations, requestId: 'b2'), 0);
      expect(unreadTotal(conversations, requestId: 'missing'), 0);
    });

    test('empty list → 0', () {
      expect(unreadTotal(const []), 0);
    });
  });
}
