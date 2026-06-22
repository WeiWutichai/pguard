import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/available_guard.dart';
import '../models/booking.dart';
import '../models/booking_options.dart';
import '../models/geo.dart';
import '../models/money.dart';
import '../models/service_catalog.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'locale_controller.dart';

part 'booking_flow_controller.g.dart';

const Object _unset = Object();

/// Cross-screen state for the customer book-a-guard flow (service → form → discovery). One
/// shared session object instead of v1's ~12 constructor args threaded across the screens. All
/// money is held as integer satang (see [Money]). v2 is POST-PAY: the customer is NOT charged
/// here — the booking is created (carrying the chosen `tip`), a guard accepts, and the bill is
/// raised on completion for the actual hours (seen on live-status / the wallet).
class BookingFlowState {
  const BookingFlowState({
    this.service,
    this.place,
    this.address = '',
    this.startAt,
    this.endAt,
    this.extraDetails = '',
    this.equipment = const {},
    this.addOns = const {},
    this.guardCount = 1,
    this.tipSatang = 0,
    this.booking,
    this.guards = const [],
    this.selectedGuardId,
    this.busy = false,
    this.error,
  });

  /// Selected catalog service (from `GET /v1/services`). Its `id` is sent as the booking's
  /// `service_id` (the server then prices from its `base_fee` and enforces its `min_hours`); its
  /// `baseFeeSatang` drives the pre-booking ESTIMATE only — the client never sends a price.
  final ServiceOption? service;

  /// Map-picked coordinate + place name (UX/draft only — only [address] is sent).
  final GeoPlace? place;

  /// The location address chosen on the form (the map pin's resolved name or the typed text). NOT
  /// sent verbatim — [composedAddress] folds the extra details/equipment/add-ons into it before it
  /// is sent as the booking's `address`.
  final String address;

  /// The booking's start instant — the form's start date+time picker. Sent as `scheduled_at`
  /// (RFC3339 UTC). Null until the customer picks a start.
  final DateTime? startAt;

  /// The booking's end instant — the form's end date+time picker (or a quick-preset `start +
  /// preset hours`). The form COMPUTES `hours = (end − start)` from this; the end itself is not
  /// sent. Null until set.
  final DateTime? endAt;

  /// Free-text "รายละเอียดเพิ่มเติม" note — folded into the sent `address` (no backend field).
  final String extraDetails;

  /// Selected security-equipment ids (subset of [kSecurityEquipment]) — folded into the address;
  /// no price effect.
  final Set<String> equipment;

  /// Selected add-on-service ids (subset of [kAddOnServices]) — folded into the address; no price
  /// effect.
  final Set<String> addOns;

  final int guardCount;

  /// Optional flat tip (satang), chosen on the booking form and sent with the booking — the
  /// post-pay bill adds it in full on completion (never prorated).
  final int tipSatang;

  /// The created booking — carries the SERVER-OWNED [Booking.baseFee].
  final Booking? booking;
  final List<AvailableGuard> guards;

  /// Discovery preview selection. v2 is first-come-accept, so this does NOT assign the guard;
  /// it only highlights the customer's preferred guard in the UI.
  final String? selectedGuardId;
  final bool busy;
  final String? error;

  // --- derived display values ---------------------------------------------------------------

  /// The booking start instant sent as `scheduled_at` — an alias of [startAt] (the form's time
  /// model is start/end; this keeps the rest of the flow speaking "scheduled_at").
  DateTime? get scheduledAt => startAt;

  /// Computed whole hours `(end − start)` — the value sent as the booking's `hours`. 0 until both
  /// ends are set / when the range is non-positive (the form warns/blocks before send).
  int get hours => hoursBetween(startAt, endAt);

  /// Whether the chosen range meets the selected service's [minHours] (server-enforced too). The
  /// form shows an inline "ขั้นต่ำ N ชม." warning and blocks the CTA when this is false.
  bool get meetsMinHours => hours >= minHours;

  /// The single `address` string actually sent to `POST /v1/bookings`: the chosen location address
  /// with the extra-details note + selected equipment + selected add-ons folded in as labelled
  /// lines (see [composeAddress]). The locale is resolved by the controller at send time.
  String composedAddressFor(bool isThai) => composeAddress(
        address: address,
        extraDetails: extraDetails,
        equipment: equipment,
        addOns: addOns,
        isThai: isThai,
      );

  /// Indicative ฿/hr (satang) from the selected catalog service — an ESTIMATE shown before
  /// booking (the authoritative rate is the created booking's server-owned `base_fee`).
  int get estimateHourlySatang => service?.baseFeeSatang ?? 0;

  /// Pre-booking estimate total (satang) = indicative rate × hours × guards. Display only.
  int get estimateTotalSatang => estimateHourlySatang * hours * guardCount;

  /// Estimate total including the chosen flat tip (satang) — the form's headline figure. Still an
  /// ESTIMATE; the authoritative bill (actual hours + tip) is raised on completion.
  int get estimateWithTipSatang => estimateTotalSatang + tipSatang;

  /// Whether the selected service has an indicative price to show (a positive base_fee).
  bool get hasEstimate => (service?.baseFeeSatang ?? 0) > 0;

  /// The minimum bookable hours for the current selection (the selected service's `min_hours`,
  /// at least 1). Floors the form's hours field; the server enforces it authoritatively.
  int get minHours {
    final m = service?.minHours ?? 1;
    return m < 1 ? 1 : m;
  }

  /// The booked end instant (start + booked hours; server values when present) — drives the
  /// success screen's "14:00 – 22:00" time-range row. Display only; `null` until scheduled. Falls
  /// back to the form's [endAt] when there is no server-confirmed booking yet.
  DateTime? get scheduledEndAt {
    final b = booking;
    if (b?.scheduledAt != null) {
      return b!.scheduledAt!.add(Duration(hours: b.hours ?? hours));
    }
    return endAt;
  }

  BookingFlowState copyWith({
    ServiceOption? service,
    GeoPlace? place,
    String? address,
    DateTime? startAt,
    DateTime? endAt,
    String? extraDetails,
    Set<String>? equipment,
    Set<String>? addOns,
    int? guardCount,
    int? tipSatang,
    Booking? booking,
    List<AvailableGuard>? guards,
    String? selectedGuardId,
    bool? busy,
    Object? error = _unset,
  }) {
    return BookingFlowState(
      service: service ?? this.service,
      place: place ?? this.place,
      address: address ?? this.address,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      extraDetails: extraDetails ?? this.extraDetails,
      equipment: equipment ?? this.equipment,
      addOns: addOns ?? this.addOns,
      guardCount: guardCount ?? this.guardCount,
      tipSatang: tipSatang ?? this.tipSatang,
      booking: booking ?? this.booking,
      guards: guards ?? this.guards,
      selectedGuardId: selectedGuardId ?? this.selectedGuardId,
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

  /// Whether the app is rendering in Thai — used to localize the error messages
  /// this controller stores in [BookingFlowState.error] for the screens to show.
  bool get _isThai => ref.read(localeControllerProvider) == AppLocale.th;

  /// Start a fresh booking (called when the flow is entered).
  void reset() => state = const BookingFlowState();

  /// Select a catalog service. When a start is already chosen, extends the end up to the service's
  /// `min_hours` floor (so the duration starts at — and the warning clears above — the admin-set
  /// minimum the server enforces). Pure clamp; the form's preset chips do the same on tap.
  void selectService(ServiceOption service) {
    final start = state.startAt;
    DateTime? end = state.endAt;
    if (start != null && (end == null || hoursBetween(start, end) < service.minHours)) {
      end = start.add(Duration(hours: service.minHours));
    }
    state = state.copyWith(service: service, endAt: end, error: null);
  }

  /// Set the location from the map picker / place search — stores the coordinate AND fills the
  /// editable [address] with the resolved place name (the extras are folded in at send time).
  void setLocation(GeoPlace place) => state =
      state.copyWith(place: place, address: place.placeName, error: null);

  void setAddress(String address) =>
      state = state.copyWith(address: address, error: null);

  void setExtraDetails(String details) =>
      state = state.copyWith(extraDetails: details, error: null);

  /// Set the start instant. Keeps a chosen end consistent: if the end is now at/before the start,
  /// it is re-anchored to `start + minHours` so the duration never goes non-positive.
  void setStart(DateTime when) {
    final end = state.endAt;
    final fixedEnd = (end == null || !end.isAfter(when))
        ? when.add(Duration(hours: state.minHours))
        : end;
    state = state.copyWith(startAt: when, endAt: fixedEnd, error: null);
  }

  /// Set the end instant directly (the end date+time picker). The form/server enforce min-hours;
  /// this stores the raw pick so the live duration + warning update.
  void setEnd(DateTime when) => state = state.copyWith(endAt: when, error: null);

  /// Quick-preset: set the end to `start + hours` (a "12 ชม."/"8 ชม." chip). Anchors the start to
  /// now when none is chosen yet so a preset alone produces a complete, valid range.
  void setDurationPreset(int presetHours) {
    final start = state.startAt ?? _defaultStart();
    state = state.copyWith(
        startAt: start,
        endAt: start.add(Duration(hours: presetHours)),
        error: null);
  }

  /// Toggle one security-equipment id in/out of the selection.
  void toggleEquipment(String id) =>
      state = state.copyWith(equipment: _toggled(state.equipment, id), error: null);

  /// Toggle one add-on-service id in/out of the selection.
  void toggleAddOn(String id) =>
      state = state.copyWith(addOns: _toggled(state.addOns, id), error: null);

  void setGuardCount(int count) =>
      state = state.copyWith(guardCount: count.clamp(1, 20), error: null);

  void setTipSatang(int satang) =>
      state = state.copyWith(tipSatang: satang < 0 ? 0 : satang, error: null);

  /// Immutable toggle of [id] in/out of [set].
  static Set<String> _toggled(Set<String> set, String id) {
    final next = {...set};
    if (!next.remove(id)) next.add(id);
    return next;
  }

  /// A sensible default start when a preset is tapped before a start is picked: the next whole hour
  /// from now (so the booking is in the future and minute-clean).
  static DateTime _defaultStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour)
        .add(const Duration(hours: 1));
  }

  void selectGuard(String guardId) =>
      state = state.copyWith(selectedGuardId: guardId, error: null);

  /// `POST /v1/bookings` — create the request, carrying the chosen flat `tip`. Stores the
  /// authoritative [Booking] (with the server-owned `base_fee`). No charge happens here (post-pay).
  Future<bool> createBooking() => _guard(() async {
        if (state.address.trim().isEmpty) {
          state = state.copyWith(
              error: _isThai ? 'กรุณาระบุสถานที่' : 'Enter a location');
          return false;
        }
        // The form's time model is start + end → compute whole hours and map to the unchanged
        // backend body (scheduled_at = start, hours = computed). Default to the next hour for a
        // minimum-length window if the customer somehow reached create without a start.
        final start = state.startAt ??
            DateTime.now().toUtc().add(const Duration(hours: 1));
        final hours = state.startAt == null ? state.minHours : state.hours;
        // Enforce the selected service's min_hours client-side (the server enforces it too).
        if (hours < state.minHours) {
          state = state.copyWith(
              error: _isThai
                  ? 'ระยะเวลาบริการขั้นต่ำ ${state.minHours} ชม.'
                  : 'Minimum service time is ${state.minHours} hours');
          return false;
        }
        // Fold the chosen location address + extra details + selected equipment/add-ons into the
        // single free-text `address` the contract carries (no backend field for the extras).
        final address = state.composedAddressFor(_isThai);
        final place = state.place;
        final service = state.service;
        final data = await ref.read(pguardApiProvider).post('/bookings', data: {
          'address': address,
          'scheduled_at': start.toUtc().toIso8601String(),
          'hours': hours,
          'guard_count': state.guardCount,
          // The chosen catalog service: send ONLY its id. The server prices the booking from that
          // service's base_fee and enforces its min_hours — the client never sends a price.
          if (service != null) 'service_id': service.id,
          // Send the map-pinned site coordinate when the customer picked one (the contract's
          // optional lat/lng — both-or-neither). Lets the guard see the job location and feeds
          // open-job radius discovery server-side. Omitted when only a typed address was used.
          if (place != null) ...{
            'lat': place.point.lat,
            'lng': place.point.lng,
          },
          // Flat tip chosen on the form. Post-pay bills it in full (never prorated) on completion.
          'tip': Money.amountString(state.tipSatang),
        });
        final booking = Booking.fromJson(data as Map<String, dynamic>);
        // Pin the form's start onto the state so any later read (success screen) has a start even
        // when the customer relied on the create-time fallback above.
        state = state.copyWith(booking: booking, startAt: start);
        return true;
      });

  /// `GET /v1/available-guards` — discovery preview. The endpoint takes no params and returns
  /// approved guards enriched with their rating summary. v2 is first-come-accept, so this is a
  /// preview of who is available; a nearby guard accepts the request later (seen on live-status).
  Future<bool> loadGuards() => _guard(() async {
        final data = await ref.read(pguardApiProvider).get('/available-guards');
        final list = (data as List)
            .whereType<Map<String, dynamic>>()
            .map(AvailableGuard.fromJson)
            .toList();
        state = state.copyWith(guards: list);
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
          busy: false,
          error: _isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong');
      return false;
    }
  }
}
