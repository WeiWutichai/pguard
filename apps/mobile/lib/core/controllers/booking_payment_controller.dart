import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/payment.dart';
import '../providers.dart';

part 'booking_payment_controller.g.dart';

/// The customer's RECONCILED payment for ONE booking — the data the job-completion summary
/// reads to show the settled `final_amount` / `refund_amount`.
///
/// Payment-read used: `GET /v1/payments` (`listPayments` in `contracts/openapi/payment.yaml`)
/// — the caller's own payments, newest first. There is NO `?booking_id=` filter on that
/// endpoint, and `GET /payments/{id}` keys by PAYMENT id (which the client does not know),
/// so we pull the owner-scoped list and pick the row whose `booking_id` matches. v2 is
/// post-pay with one payment per booking, so the match is unambiguous; if no row is found
/// (the `booking.completed` → `payment.completed` settle has not landed yet, or the gateway
/// hasn't propagated it), it returns `null` and the summary falls back to deriving the cost
/// from the booking + notes the gap.
///
/// One fetch per controller lifetime (no `Timer.periodic`); the summary is reached on the WS
/// `completed` frame, so the settle is already in flight — the screen offers a manual retry.
@riverpod
class BookingPaymentController extends _$BookingPaymentController {
  @override
  Future<Payment?> build(String bookingId) async {
    final data = await ref.read(pguardApiProvider).get('/payments');
    final raw = data is List ? data : const [];
    for (final row in raw.whereType<Map<String, dynamic>>()) {
      final payment = Payment.fromJson(row);
      if (payment.bookingId == bookingId) return payment;
    }
    return null;
  }
}
