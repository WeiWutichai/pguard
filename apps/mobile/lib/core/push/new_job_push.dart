/// A decoded "new job nearby" FCM data message.
///
/// The notification service fans `pguard.events.booking.requested` out to each online guard as a
/// push whose `data` carries `{ type: "new_job", booking_id }` (mirrors the `incoming_call` push
/// shape — see `incoming_call_push.dart`). FCM `data` values are ALWAYS strings on the wire.
class NewJobPush {
  const NewJobPush({required this.bookingId});

  final String bookingId;

  /// Parse an FCM `data` map into a [NewJobPush], or `null` when it is not a new-job push
  /// (wrong/absent `type`, or no usable `booking_id`). Pure — no platform channels — so the push
  /// routing is unit-testable without Firebase. The `booking_id` is optional in practice: even
  /// without it the push is recognised (it still means "refresh the open feed"), so an empty/absent
  /// id parses to an empty [bookingId] rather than `null`.
  static NewJobPush? tryParse(Map<String, dynamic> data) {
    if (data['type'] != 'new_job') return null;
    final id = data['booking_id'];
    return NewJobPush(bookingId: id is String ? id : '');
  }
}
