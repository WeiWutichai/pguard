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
  });

  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final bool isRead;
  final DateTime sentAt;
  final DateTime? readAt;

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
      );

  AppNotification copyWith({bool? isRead, DateTime? readAt}) => AppNotification(
        id: id,
        title: title,
        body: body,
        type: type,
        isRead: isRead ?? this.isRead,
        sentAt: sentAt,
        readAt: readAt ?? this.readAt,
      );
}
