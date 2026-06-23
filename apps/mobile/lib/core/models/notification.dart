// Notification domain model — mirrors `contracts/openapi/notification.yaml` (`NotificationLog`).
// Pure (no Flutter) → unit-testable. NOTE the wire field names: message text is `body` (not
// `message`), the read flag is `is_read` (not `read`), the timestamp is `sent_at` (not
// `created_at`), and the kind is `notification_type` (not `type`).

/// The notification kind (snake_case wire values from the `NotificationType` enum).
enum NotificationType {
  bookingCreated('booking_created'),
  guardAssigned('guard_assigned'),
  guardEnRoute('guard_en_route'),
  guardArrived('guard_arrived'),
  bookingCompleted('booking_completed'),
  bookingCancelled('booking_cancelled'),
  chatMessage('chat_message'),
  system('system');

  const NotificationType(this.wire);

  final String wire;

  /// Parse a wire value; falls back to [system] for unknown/forward-compat types.
  static NotificationType parse(String? value) {
    for (final t in NotificationType.values) {
      if (t.wire == value) return t;
    }
    return NotificationType.system;
  }
}

/// One notification as returned by `GET /v1/notifications`.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.sentAt,
    this.readAt,
    this.payload = const {},
  });

  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final bool isRead;
  final DateTime sentAt;
  final DateTime? readAt;

  /// The free-form `payload` the notification service stores alongside each notification (see
  /// `services/notification/src/domain/mapping.rs` `build_data`). Carries the reference ids that
  /// drive tap-through navigation: `booking_id`, `conversation_id`, `call_id`, plus `event_type`
  /// / `target_role`. Always present (defaults to empty) so the resolver is null-safe.
  final Map<String, dynamic> payload;

  /// A reference id from [payload], as a non-empty string, or null. FCM `data` values are always
  /// strings on the wire and the persisted payload mirrors that, so this just trims to non-empty.
  String? _id(String key) {
    final v = payload[key];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  String? get bookingId => _id('booking_id');
  String? get conversationId => _id('conversation_id');
  String? get callId => _id('call_id');

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        type: NotificationType.parse(json['notification_type'] as String?),
        isRead: json['is_read'] as bool? ?? false,
        sentAt: DateTime.tryParse(json['sent_at'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        readAt: json['read_at'] != null
            ? DateTime.tryParse(json['read_at'] as String)?.toUtc()
            : null,
        payload: json['payload'] is Map<String, dynamic>
            ? json['payload'] as Map<String, dynamic>
            : const {},
      );

  AppNotification copyWith({bool? isRead, DateTime? readAt}) => AppNotification(
        id: id,
        title: title,
        body: body,
        type: type,
        isRead: isRead ?? this.isRead,
        sentAt: sentAt,
        readAt: readAt ?? this.readAt,
        payload: payload,
      );
}
