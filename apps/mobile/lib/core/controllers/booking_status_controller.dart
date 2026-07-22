import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/booking.dart';
import '../network/api_error_l10n.dart';
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
    // Carry forward a `paidAt` already known to the live state (e.g. an optimistic [markPaid]
    // from the payment success) onto this fresh snapshot — `paid` is MONOTONIC, so a re-build /
    // re-pull whose snapshot lacks `paid_at` (the booking service sets it ASYNC, ~1s after the
    // charge) must never DOWNGRADE a paid booking back to unpaid (that flicker is the reported
    // pay-loop). [_mergePaid] keeps whichever side is paid.
    booking = _mergePaid(booking, state.valueOrNull);

    // Recover status changes MISSED during a WS gap. The hub only forwards LIVE events and sends no
    // snapshot on subscribe, so a transition that happened while the socket was down (a customer
    // reject → arrived, a cancel) reaches nobody. On each RECONNECT edge, re-pull the REST snapshot
    // (deep-review HIGH: the guard was otherwise stuck on 'รอลูกค้าตรวจสอบ' / drove to a cancelled
    // site). Baseline `true` so the initial connect below — whose snapshot we JUST fetched — is not
    // treated as a reconnect. Best-effort + monotonic-paid.
    var wasConnected = true;
    final StreamSubscription<bool> connSub =
        feed.connectionChanges.listen((connected) async {
      final reconnected = connected && !wasConnected;
      wasConnected = connected;
      if (!reconnected) return;
      try {
        final fresh = await api.get('/bookings/$bookingId');
        final merged = _mergePaid(
            Booking.fromJson(fresh as Map<String, dynamic>), state.valueOrNull);
        booking = merged;
        state = AsyncData(merged);
      } catch (_) {
        // Leave the last-known state; a live frame or a manual action will correct it.
      }
    });

    ref.onDispose(() {
      sub.cancel();
      connSub.cancel();
      feed.close();
    });
    await feed.connect();

    return booking;
  }

  /// Optimistically mark this booking PAID the instant the customer's `POST /payments` succeeds,
  /// so the live-status pay banner (and the PaymentScreen's pay panel) disappear IMMEDIATELY —
  /// without waiting for the booking service to consume `payment.completed` and set `paid_at`
  /// (it does that ASYNC, ~1s later). Stamps `paidAt = now` only if not already set, and is a
  /// no-op once the booking is already paid (idempotent). Because [build] and [applyEvent] both
  /// carry `paidAt` forward, this paid state then SURVIVES every later snapshot/WS frame — a stale
  /// unpaid snapshot can never un-pay it (the monotonic guarantee that kills the pay-loop).
  void markPaid() {
    final current = state.valueOrNull;
    if (current == null || current.isPaid) return;
    state = AsyncData(current.withPaidAt(DateTime.now().toUtc()));
  }

  /// Keep whichever of [snapshot]/[previous] is PAID — `paid` never downgrades. Returns [snapshot]
  /// with its `paidAt` filled from [previous] when the fresh snapshot lacks one but a prior state
  /// already knew the booking was paid.
  static Booking _mergePaid(Booking snapshot, Booking? previous) {
    if (snapshot.paidAt != null || previous?.paidAt == null) return snapshot;
    return snapshot.withPaidAt(previous!.paidAt!);
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
      return _localizeBookingConflict(e);
    } catch (_) {
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      return isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong';
    }
  }

  /// A 409 here is a raced state transition (the guard flipped to arrived just as the customer
  /// cancelled, or an approve/reject race) — the server's message is an English contract sentence,
  /// so localize it for Thai users; every other case defers to the shared helper (deep-review).
  String _localizeBookingConflict(ApiException e) {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    if (e.statusCode == 409) {
      return isThai
          ? 'สถานะงานเปลี่ยนไปแล้ว โหลดข้อมูลล่าสุดแล้วลองใหม่'
          : localizeApiError(false, e);
    }
    return localizeApiError(isThai, e);
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
      return _localizeBookingConflict(e);
    } catch (_) {
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      return isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong';
    }
  }
}
