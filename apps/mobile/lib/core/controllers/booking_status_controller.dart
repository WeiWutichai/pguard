import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/booking.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'locale_controller.dart';

part 'booking_status_controller.g.dart';

/// Live booking-status controller — THE Phase 2 point: status arrives by WebSocket PUSH, not
/// `Timer.periodic` REST polling (v1's 13-timer anti-pattern).
///
/// On open it fetches ONE REST snapshot (`GET /v1/bookings/{id}`) for the initial state, then
/// subscribes to the booking-status feed and folds each pushed [BookingStatusEvent] into the
/// booking. There is no timer in this path; the feed's own reconnect is event-driven backoff.
@riverpod
class BookingStatusController extends _$BookingStatusController {
  @override
  Future<Booking> build(String bookingId) async {
    final api = ref.read(pguardApiProvider);

    // One-shot initial snapshot (single fetch — NOT polling).
    final data = await api.get('/bookings/$bookingId');
    var booking = Booking.fromJson(data as Map<String, dynamic>);

    // Subscribe to live pushes. Each (re)connect gets a FRESH, non-expired Bearer via
    // validAccessToken (so a reconnect after a long drop doesn't loop on a dead token).
    final feed = ref.read(bookingStatusFeedBuilderProvider)(
      bookingId,
      () => api.validAccessToken(),
    );
    final StreamSubscription<BookingStatusEvent> sub =
        feed.events.listen((event) {
      final current = state.valueOrNull ?? booking;
      booking = current.applyEvent(event);
      state = AsyncData(booking);
    });
    ref.onDispose(() {
      sub.cancel();
      feed.close();
    });
    await feed.connect();

    return booking;
  }

  /// `PUT /v1/bookings/{id}/cancel` — the customer cancels PRE-ARRIVAL
  /// (`requested`/`accepted`/`en_route` → `cancelled`), per `cancelBooking` in
  /// `contracts/openapi/booking.yaml`. The contract takes NO request body, so [reason]
  /// is DISPLAY-ONLY (the cancellation screen collects it for UX; it is never sent —
  /// no such API field exists). On success the returned booking is folded into state
  /// immediately (the WS `cancelled` frame that follows is idempotent).
  ///
  /// Returns `null` on success, else a human-readable error message for a SnackBar.
  Future<String?> cancel({String? reason}) async {
    try {
      final data =
          await ref.read(pguardApiProvider).put('/bookings/$bookingId/cancel');
      state = AsyncData(Booking.fromJson(data as Map<String, dynamic>));
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      return isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong';
    }
  }

  /// `PUT /v1/bookings/{id}/review-completion { action }` — the customer (request owner)
  /// rules on the guard's completion request (`reviewCompletion` in `booking.yaml`). Allowed
  /// only while the booking is `pending_completion`:
  ///  - `approve` → `completed` (emits `pguard.events.booking.completed`, which drives the
  ///    payment RECONCILE: the pre-pay charge is settled to the hours actually worked, any
  ///    overpay refunded);
  ///  - `reject` → back to `arrived` (the guard keeps working).
  ///
  /// On success the returned booking is folded into state immediately (the WS frame that
  /// follows is idempotent). Returns `null` on success, else a human-readable error message.
  Future<String?> reviewCompletion({required bool approve}) async {
    try {
      final data = await ref.read(pguardApiProvider).put(
        '/bookings/$bookingId/review-completion',
        data: {'action': approve ? 'approve' : 'reject'},
      );
      state = AsyncData(Booking.fromJson(data as Map<String, dynamic>));
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      return isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong';
    }
  }
}
