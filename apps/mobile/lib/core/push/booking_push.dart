/// A decoded foreground FCM `data` push that should refresh a specific booking's live state.
///
/// The notification service stamps every persisted push with the source `event_type` (the
/// originating `pguard.events.*` topic) plus the reference ids it carried — including `booking_id`
/// (see `services/notification/src/domain/mapping.rs::build_data`). Two of those event families
/// must re-pull the booking on the receiving device:
///   - `pguard.events.payment.completed` — the booking service sets `paid_at` ASYNC off this same
///     event, so the guard's active-job screen must re-fetch to UN-GATE "Go en route" (and the
///     customer's live screen to drop the pay banner);
///   - `pguard.events.booking.*` — any booking status transition (en_route / arrived / …).
///
/// Carries the `booking_id` so the push handler can invalidate exactly that booking's controllers.
/// PURE (no Flutter / Firebase) so the routing is unit-testable. FCM `data` values are ALWAYS
/// strings on the wire. `new_job` is deliberately NOT matched here — it has its own parser/handler
/// (it refreshes the open-jobs feed, not a single booking).
class BookingPush {
  const BookingPush({required this.bookingId, required this.isPayment});

  /// The booking this push concerns. Empty when the push carried no `booking_id` (still a
  /// recognised booking/payment update — the handler simply has nothing specific to refresh).
  final String bookingId;

  /// Whether this is the `payment.completed` push (the guard's pay gate releases off it). Lets the
  /// handler apply the extra "paid_at is async" retry only where it matters.
  final bool isPayment;

  /// Parse an FCM `data` map into a [BookingPush], or `null` when it is not a payment/booking push.
  /// Matched on `event_type` (these pushes carry no top-level `type`); the `new_job` push (which
  /// DOES carry `type`) is excluded so its own handler keeps ownership.
  static BookingPush? tryParse(Map<String, dynamic> data) {
    if (data['type'] != null) return null; // new_job / incoming_call own those
    final eventType = data['event_type'];
    if (eventType is! String) return null;
    final isPayment = eventType == 'pguard.events.payment.completed';
    final isBooking = eventType.startsWith('pguard.events.booking.');
    if (!isPayment && !isBooking) return null;
    final id = data['booking_id'];
    return BookingPush(bookingId: id is String ? id : '', isPayment: isPayment);
  }
}
