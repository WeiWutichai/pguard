import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/payment.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'booking_status_controller.dart';
import 'locale_controller.dart';

part 'payment_controller.g.dart';

const Object _unset = Object();

/// The customer PRE-PAY step. v2 charges the ESTIMATE (`base_fee × booked-hours × guard_count +
/// tip`) up front, the instant a guard ACCEPTS — and the bill is RECONCILED on completion (actual
/// hours → settle, refunding any over-charge). The amount is computed SERVER-SIDE from the
/// authoritative booking (`GET /internal/bookings/{id}`); the client NEVER sends it — it posts
/// only `{ booking_id }`. On success the payment service emits `pguard.events.payment.completed`,
/// which the booking service consumes to set `paid_at` and UN-GATE the guard's `en_route`.
///
/// This is the network + state for the [PaymentScreen]: the screen renders [PaymentState] and
/// calls [createPayment]; the (estimate) figure shown is read from the booking, not from here.
class PaymentState {
  const PaymentState({
    this.busy = false,
    this.payment,
    this.error,
    this.slipRequired = false,
  });

  /// In-flight `POST /payments`.
  final bool busy;

  /// The created payment once the charge has cleared (status `completed`). `null` before the
  /// customer pays. Its presence is the "PaymentSuccess" signal the screen waits on.
  final Payment? payment;

  /// Localized failure message for the last attempt, else `null`.
  final String? error;

  /// `true` when `POST /payments` came back `409 SLIP_REQUIRED` — the provider is `slip2go`, so
  /// there is no auto-charge: the customer must transfer via PromptPay and upload a slip. The
  /// screen switches to the slip flow ([SlipPaymentController] / the PromptPay panel). Under the
  /// simulated default this stays `false` and the existing one-tap pay path is unchanged.
  final bool slipRequired;

  /// Whether the pre-pay charge has cleared (the screen flips to "waiting for the guard").
  bool get isPaid => payment != null;

  PaymentState copyWith({
    bool? busy,
    Payment? payment,
    Object? error = _unset,
    bool? slipRequired,
  }) =>
      PaymentState(
        busy: busy ?? this.busy,
        payment: payment ?? this.payment,
        error: identical(error, _unset) ? this.error : error as String?,
        slipRequired: slipRequired ?? this.slipRequired,
      );
}

/// Drives the PRE-PAY charge for one booking. Per-booking instance (the `bookingId` family arg)
/// so two bookings never share pay state. Mutating method returns `bool` so the screen knows
/// whether the charge succeeded (mirrors [BookingFlowController]).
@riverpod
class PaymentController extends _$PaymentController {
  @override
  PaymentState build(String bookingId) => const PaymentState();

  bool get _isThai => ref.read(localeControllerProvider) == AppLocale.th;

  /// `POST /v1/payments { booking_id }` — pay the server-computed estimate. The client sends
  /// ONLY the booking id; the payment service reads the authoritative booking, computes the
  /// amount, charges it, and returns the (completed) [Payment]. On success the customer moves to
  /// the success state and waits (over the booking-status WS) for the guard to proceed.
  ///
  /// Returns `true` on success. Idempotent-friendly: if a prior attempt already paid (a 409 /
  /// already-paid response, or a returned `completed` payment), the screen still lands on success.
  Future<bool> createPayment() async {
    if (state.isPaid) return true;
    state = state.copyWith(busy: true, error: null);
    try {
      final data = await ref
          .read(pguardApiProvider)
          .post('/payments', data: {'booking_id': bookingId});
      final payment = Payment.fromJson(data as Map<String, dynamic>);
      state = state.copyWith(busy: false, payment: payment, error: null);
      // OPTIMISTICALLY mark the LIVE booking paid now, so the pay banner (PaymentScreen + the
      // live-status screen's _PayNowBanner) disappears immediately — and, because that paid flag
      // is MONOTONIC (carried forward across snapshots/WS frames), it never flickers back when a
      // stale snapshot arrives before the booking service sets `paid_at` (~1s async). This is what
      // breaks the reported pay-loop. Only touch the live controller when it is already alive (the
      // PaymentScreen watches it), so we never spin one up just to mutate it.
      if (ref.exists(bookingStatusControllerProvider(bookingId))) {
        ref.read(bookingStatusControllerProvider(bookingId).notifier).markPaid();
      }
      return true;
    } on ApiException catch (e) {
      // The provider requires a transfer slip (PAYMENT_PROVIDER=slip2go): there is no auto-charge.
      // Flip to the slip flow instead of surfacing this as an error — the screen renders the
      // PromptPay QR + slip upload. (Branch on the CODE, not the message.)
      if (e.code == 'SLIP_REQUIRED') {
        state = state.copyWith(busy: false, slipRequired: true, error: null);
        return false;
      }
      state = state.copyWith(busy: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        busy: false,
        error: _isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong',
      );
      return false;
    }
  }
}
