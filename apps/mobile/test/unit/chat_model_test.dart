import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/media/media_host.dart';
import 'package:pguard_mobile/core/models/chat.dart';

void main() {
  group('ChatMessage.tryParse / fromJson', () {
    Map<String, dynamic> frame({String? type, String? id = 'm1'}) => {
          if (type != null) 'type': type,
          if (id != null) 'id': id,
          'conversation_id': 'cv1',
          'sender_id': 's1',
          'sender_role': 'guard',
          'content': 'hi',
          'message_type': 'text',
          'created_at': '2026-06-05T10:00:00Z',
        };

    test('parses a well-formed message frame', () {
      final m = ChatMessage.tryParse(frame());
      expect(m, isNotNull);
      expect(m!.id, 'm1');
      expect(m.conversationId, 'cv1');
      expect(m.senderRole, 'guard');
      expect(m.content, 'hi');
      expect(m.type, ChatMessageType.text);
    });

    test('returns null for a server error frame', () {
      expect(ChatMessage.tryParse({'type': 'error', 'message': 'nope'}), isNull);
    });

    test('returns null for a malformed frame (no id / conversation_id)', () {
      expect(ChatMessage.tryParse(frame(id: null)), isNull);
      expect(ChatMessage.tryParse({'id': 'x'}), isNull);
    });
  });

  group('alignment is by sender_role, never sender_id', () {
    ChatMessage msg(String role) => ChatMessage(
          id: 'm',
          conversationId: 'cv1',
          senderId: 'the-same-user', // identical id in both roles — must NOT decide side
          senderRole: role,
          type: ChatMessageType.text,
          createdAt: DateTime.utc(2026),
        );

    test('own role → right (isFromRole true); counterpart role → left', () {
      expect(msg('guard').isFromRole(ChatRole.guard), isTrue);
      expect(msg('guard').isFromRole(ChatRole.customer), isFalse);
      expect(msg('customer').isFromRole(ChatRole.customer), isTrue);
      expect(msg('customer').isFromRole(ChatRole.guard), isFalse);
    });
  });

  group('ChatReadOnly.fromStatus', () {
    test('completed/cancelled are read-only; others are writable', () {
      expect(ChatReadOnly.fromStatus('completed'), isTrue);
      expect(ChatReadOnly.fromStatus('cancelled'), isTrue);
      expect(ChatReadOnly.fromStatus('accepted'), isFalse);
      expect(ChatReadOnly.fromStatus('en_route'), isFalse);
      expect(ChatReadOnly.fromStatus(null), isFalse);
    });
  });

  group('ChatMessageType.parse', () {
    test('known values + forward-compatible fallback to text', () {
      expect(ChatMessageType.parse('image'), ChatMessageType.image);
      expect(ChatMessageType.parse('video'), ChatMessageType.video);
      expect(ChatMessageType.parse('system'), ChatMessageType.system);
      expect(ChatMessageType.parse('text'), ChatMessageType.text);
      expect(ChatMessageType.parse('something_new'), ChatMessageType.text);
      expect(ChatMessageType.parse(null), ChatMessageType.text);
    });
  });

  group('Conversation', () {
    test('fromJson maps the enriched fields + unread/read-only helpers', () {
      final c = Conversation.fromJson({
        'id': 'cv1',
        'request_id': 'r1',
        'created_at': '2026-06-05T10:00:00Z',
        'unread_count': 3,
        'participant_name': 'Somchai',
        'last_message': 'on my way',
        'last_message_at': '2026-06-05T10:05:00Z',
        'request_status': 'accepted',
      });
      expect(c.id, 'cv1');
      expect(c.requestId, 'r1');
      expect(c.participantName, 'Somchai');
      expect(c.unreadCount, 3);
      expect(c.hasUnread, isTrue);
      expect(c.isReadOnly, isFalse);
    });

    test('a completed booking conversation is read-only with no unread', () {
      final c = Conversation.fromJson({
        'id': 'cv2',
        'request_id': 'r2',
        'created_at': '2026-06-05T10:00:00Z',
        'unread_count': 0,
        'request_status': 'completed',
      });
      expect(c.hasUnread, isFalse);
      expect(c.isReadOnly, isTrue);
    });
  });

  group('Attachment.messageType', () {
    test('video MIME → video, otherwise image', () {
      Attachment a(String mime) =>
          Attachment(id: 'a', chatId: 'cv1', fileUrl: 'u', mimeType: mime);
      expect(a('video/mp4').messageType, ChatMessageType.video);
      expect(a('image/jpeg').messageType, ChatMessageType.image);
      expect(a('image/png').messageType, ChatMessageType.image);
    });
  });

  group('MediaHost.rewrite', () {
    test('swaps scheme+authority for the public host, keeping path + signature', () {
      expect(
        MediaHost.rewrite('http://minio:9000/chat/cv1/a.jpg?sig=abc',
            publicHost: 'https://media.pguard.app'),
        'https://media.pguard.app/chat/cv1/a.jpg?sig=abc',
      );
    });

    test('no-op when the public host is empty', () {
      expect(
        MediaHost.rewrite('http://minio:9000/a.jpg', publicHost: ''),
        'http://minio:9000/a.jpg',
      );
    });

    test('passes through a non-absolute / non-http reference unchanged', () {
      expect(MediaHost.rewrite('/relative/a.jpg', publicHost: 'https://m.x'),
          '/relative/a.jpg');
    });

    test('preserves a percent-encoded signature byte-for-byte (no re-encode)', () {
      expect(
        MediaHost.rewrite(
            'http://minio:9000/chat/x.jpg?X-Amz-Signature=AbC%2F123%2Bz',
            publicHost: 'https://media.pguard.app'),
        'https://media.pguard.app/chat/x.jpg?X-Amz-Signature=AbC%2F123%2Bz',
      );
    });
  });
}
