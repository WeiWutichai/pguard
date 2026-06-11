import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/available_guard.dart';
import '../models/booking.dart';
import '../models/geo.dart';
import '../models/money.dart';
import '../models/payment.dart';
import '../models/service_catalog.dart';
import '../network/api_exception.dart';
import '../providers.dart';

part 'booking_flow_controller.g.dart';

const Object _unset = Object();

/// Cross-screen state for the customer book-a-guard flow (service → form → discovery →
/// payment). One shared session object instead of v1's ~12 constructor args threaded across
/// five screens. All money is held as integer satang (see [Money]); the only authoritative
/// figures come from the server (`base_fee` on the created [booking], `expected_total` on the
/// [payment]).
class BookingFlowState {
  const BookingFlowState({
    this.service,
    this.place,
    this.address = '',
    this.scheduledAt,
    this.hours = 8,
    this.guardCount = 1,
    this.tipSatang = 0,
    this.booking,
    this.guards = const [],
    this.selectedGuardId,
    this.payment,
    this.busy = false,
    this.error,
  });

  /// Selected service category (presentation only — the contract has no service_type field).
  final SecurityService? service;

  /// Map-picked coordinate + place name (UX/draft only — only [address] is sent).
  final GeoPlace? place;

  /// The free-text address actually sent to `POST /v1/bookings`.
  final String address;
  final DateTime? scheduledAt;
  final int hours;
  final int guardCount;

  /// Optional extra tip (satang), added on the payment screen as charge surplus.
  final int tipSatang;

  /// The created booking — carries the SERVER-OWNED [Booking.baseFee].
  final Booking? booking;
  final List<AvailableGuard> guards;

  /// Discovery preview selection. v2 is first-come-accept, so this does NOT assign the guard;
  /// it only highlights the customer's preferred guard in the UI.
  final String? selectedGuardId;
  final Payment? payment;
  final bool busy;
  final String? error;

  // --- derived display values ---------------------------------------------------------------

  /// Indicative ฿/hr (satang) from the selected service — an ESTIMATE shown before booking.
  int get estimateHourlySatang => service?.indicativeHourlySatang ?? 0;

  /// Pre-booking estimate total (satang) = indicative rate × hours × guards. Display only.
  int get estimateTotalSatang => estimateHourlySatang * hours * guardCount;

  /// Whether the selected service has an indicative price (the "Other/custom" one does not).
  bool get hasEstimate => service?.indicativeHourlySatang != null;

  /// Authoritative service subtotal (satang) once the booking exists: `base_fee × hours ×
  /// guard_count`, all from the server-owned booking. `null` until the booking is created OR if
  /// the server-owned `base_fee` is missing/unparseable (so the UI shows "not ready" rather
  /// than a misleading ฿0 that the payment service would reject).
  int? get bookingSubtotalSatang {
    final b = booking;
    if (b?.baseFee == null) return null;
    final baseFeeSatang = Money.satangFromString(b!.baseFee);
    if (baseFeeSatang <= 0) return null;
    return baseFeeSatang * (b.hours ?? hours) * (b.guardCount ?? guardCount);
  }

  /// Amount the client will send to `POST /v1/payments` (satang) = authoritative subtotal +
  /// tip. The server re-verifies it covers `expected_total`. `null` until the booking exists.
  int? get payTotalSatang {
    final subtotal = bookingSubtotalSatang;
    return subtotal == null ? null : subtotal + tipSatang;
  }

  /// The booked end instant (start + booked hours; server values when present) — drives the
  /// success screen's "14:00 – 22:00" time-range row. Display only; `null` until scheduled.
  DateTime? get scheduledEndAt {
    final start = booking?.scheduledAt ?? scheduledAt;
    if (start == null) return null;
    return start.add(Duration(hours: booking?.hours ?? hours));
  }

  BookingFlowState copyWith({
    SecurityService? service,
    GeoPlace? place,
    String? address,
    DateTime? scheduledAt,
    int? hours,
    int? guardCount,
    int? tipSatang,
    Booking? booking,
    List<AvailableGuard>? guards,
    String? selectedGuardId,
    Payment? payment,
    bool? busy,
    Object? error = _unset,
  }) {
    return BookingFlowState(
      service: service ?? this.service,
      place: place ?? this.place,
      address: address ?? this.address,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      hours: hours ?? this.hours,
      guardCount: guardCount ?? this.guardCount,
      tipSatang: tipSatang ?? this.tipSatang,
      booking: booking ?? this.booking,
      guards: guards ?? this.guards,
      selectedGuardId: selectedGuardId ?? this.selectedGuardId,
      payment: payment ?? this.payment,
      busy: busy ?? this.busy,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

/// Drives the customer booking flow against `/v1`. All network orchestration lives here, not in
/// screens — screens render [BookingFlowState] and call these methods (mutating-method returns
/// `bool` so the screen knows whether to navigate, mirroring [AuthController]).
@Riverpod(keepAlive: true)
class BookingFlowController extends _$BookingFlowController {
  @override
  BookingFlowState build() => const BookingFlowState();

  /// Start a fresh booking (called when the flow is entered).
  void reset() => state = const BookingFlowState();

  void selectService(SecurityService service) =>
      state = state.copyWith(service: service, error: null);

  /// Set the location from the map picker — stores the coordinate AND fills the sent [address]
  /// with the resolved place name.
  void setLocation(GeoPlace place) =>
      state = state.copyWith(place: place, address: place.placeName, error: null);

  void setAddress(String address) =>
      state = state.copyWith(address: address, error: null);

  void setSchedule(DateTime when) =>
      state = state.copyWith(scheduledAt: when, error: null);

  void setHours(int hours) =>
      state = state.copyWith(hours: hours.clamp(1, 24), error: null);

  void setGuardCount(int count) =>
      state = state.copyWith(guardCount: count.clamp(1, 20), error: null);

  void setTipSatang(int satang) =>
      state = state.copyWith(tipSatang: satang < 0 ? 0 : satang, error: null);

  void selectGuard(String guardId) =>
      state = state.copyWith(selectedGuardId: guardId, error: null);

  /// `POST /v1/bookings` — create the request. Stores the authoritative [Booking] (with the
  /// server-owned `base_fee`) for the payment step.
  Future<bool> createBooking() => _guard(() async {
        final address = state.address.trim();
        if (address.isEmpty) {
          state = state.copyWith(
              error: 'กรุณาระบุสถานที่ / Enter a location');
          return false;
        }
        final when = state.scheduledAt ??
            DateTime.now().toUtc().add(const Duration(hours: 1));
        final data = await ref.read(pguardApiProvider).post('/bookings', data: {
          'address': address,
          'scheduled_at': when.toUtc().toIso8601String(),
          'hours': state.hours,
          'guard_count': state.guardCount,
          // Up-front tip stays "0"; an optional tip is added at payment as charge surplus
          // (contract: amount must cover expected_total, surplus is treated as an extra tip).
        });
        final booking = Booking.fromJson(data as Map<String, dynamic>);
        state = state.copyWith(booking: booking, scheduledAt: when);
        return true;
      });

  /// `GET /v1/available-guards` — discovery preview. The endpoint takes no params and returns
  /// approved guards enriched with their rating summary. v2 is first-come-accept, so this is a
  /// preview of who is available; a nearby guard accepts the request later (seen on live-status).
  Future<bool> loadGuards() => _guard(() async {
        final data =
            await ref.read(pguardApiProvider).get('/available-guards');
        final list = (data as List)
            .whereType<Map<String, dynamic>>()
            .map(AvailableGuard.fromJson)
            .toList();
        state = state.copyWith(guards: list);
        return true;
      });

  /// `POST /v1/payments` — charge for the booking. The `amount` is DERIVED from the booking's
  /// server-owned `base_fee` (+ optional tip) and RE-VERIFIED server-side against the computed
  /// `expected_total` (the client can never undercut the price).
  Future<bool> pay(PaymentMethod method) => _guard(() async {
        final booking = state.booking;
        final total = state.payTotalSatang;
        if (booking == null || total == null) {
          state = state.copyWith(
              error: 'ยังไม่พบการจอง / Booking not ready');
          return false;
        }
        final data = await ref.read(pguardApiProvider).post('/payments', data: {
          'booking_id': booking.id,
          'amount': Money.amountString(total),
          'payment_method': method.wire,
        });
        final payment = Payment.fromJson(data as Map<String, dynamic>);
        state = state.copyWith(payment: payment);
        return true;
      });

  Future<bool> _guard(Future<bool> Function() op) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final ok = await op();
      state = state.copyWith(busy: false);
      return ok;
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
          busy: false, error: 'เกิดข้อผิดพลาด / Something went wrong');
      return false;
    }
  }
}
