import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/booking.dart';
import '../models/geo.dart';
import '../models/guard_public_profile.dart';
import '../models/rating.dart';
import '../models/tracking.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'booking_status_controller.dart';

part 'guard_location_controller.g.dart';

/// Everything the customer live-map renders, in one watchable state (the screen watches THIS
/// controller and nothing else).
class GuardTrack {
  const GuardTrack({
    required this.booking,
    this.guard,
    this.reference,
    this.profile,
    this.ratings,
  });

  /// The live booking (status drives the en-route/arrived chip + map availability).
  final Booking booking;

  /// The guard's latest fix — `null` when no guard is assigned yet, no fix is recorded (404),
  /// or the booking is no longer active so presence denies the read (403).
  final GuardLocation? guard;

  /// The customer's own device fix — the FALLBACK destination marker used only when the booking
  /// carries no pinned coordinate (legacy bookings). `null` without a GPS fix. The real
  /// destination is [destination] (the booking pin); see [target].
  final GeoPoint? reference;

  /// The assigned guard's public mini-profile (name + experience) for the tracking card. `null`
  /// when no guard is assigned, the read is denied/absent, or the enrichment fetch failed — the
  /// card then shows a generic role label (never a fabricated name).
  final GuardPublicProfile? profile;

  /// The guard's visible ratings aggregate for the tracking card. `null` when unavailable; the
  /// card shows a "no reviews yet" state rather than a fake 0.0 (see [GuardRatings.hasRatings]).
  final GuardRatings? ratings;

  BookingStatus get status => booking.status;
  String? get guardId => booking.guardId;

  /// The booking's pinned drop-off coordinate (where the guard is heading), when the customer
  /// pinned one at create time (`lat`/`lng` are both-or-neither on the contract). `null` for a
  /// legacy/address-only booking — then [target] falls back to the device fix.
  GeoPoint? get destination {
    final lat = booking.lat;
    final lng = booking.lng;
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng);
  }

  /// The point the guard is travelling to: the booking [destination] when pinned, else the
  /// customer's device [reference] as a stand-in. `null` when neither is known.
  GeoPoint? get target => destination ?? reference;

  /// `true` when [target] is the real booking pin (label it "Destination"), `false` when it is
  /// the device-fix fallback (label it "You").
  bool get targetIsDestination => destination != null;

  /// Straight-line metres between the guard and [target] (`null` when either is unknown). Reuses
  /// the shared haversine — no second implementation, no directions API (label as approximate).
  double? get distanceToTarget {
    final g = guard;
    final t = target;
    if (g == null || t == null) return null;
    return distanceMeters(g.point, t);
  }
}

/// Customer live-map controller — Phase 2 rules apply: there is NO location stream readable by
/// customers (`/ws/track` is guard-only GPS ingest), and `Timer.periodic` polling is forbidden.
/// So this controller WATCHES the booking-status controller: every status frame pushed over the
/// booking WebSocket (`guard_en_route`, `arrived`, …) re-runs [build], which re-pulls ONE
/// `GET /v1/guards/{id}/location` snapshot (plus the one-shot profile + ratings enrichment).
/// Opening the screen and the user-initiated [refresh] are the only other fetch triggers — every
/// fetch in this path is event- or gesture-driven, never a timer.
@riverpod
class GuardLocationController extends _$GuardLocationController {
  @override
  Future<GuardTrack> build(String bookingId) async {
    // Rebuilds on every pushed status event (the WS is owned by BookingStatusController, whose
    // ref.onDispose closes it — nothing to clean up here).
    final booking =
        await ref.watch(bookingStatusControllerProvider(bookingId).future);

    GuardLocation? guard;
    GuardPublicProfile? profile;
    GuardRatings? ratings;
    final guardId = booking.guardId;
    if (guardId != null) {
      // Three independent reads, concurrent. The LOCATION read is core (a non-404/403 error
      // surfaces as a screen error — see [_fetchLocation]); the profile + ratings are enrichment
      // that DEGRADE on any API error (the map still renders with a generic label / no rating).
      final results = await Future.wait([
        _fetchLocation(guardId),
        _fetchPublicProfile(guardId),
        _fetchRatings(guardId),
      ]);
      guard = results[0] as GuardLocation?;
      profile = results[1] as GuardPublicProfile?;
      ratings = results[2] as GuardRatings?;
    }

    // One-shot device fix for the fallback destination marker (injectable; null when GPS is
    // unavailable). The real destination is the booking pin (GuardTrack.destination).
    final reference = await ref.read(locationServiceProvider).currentLocation();

    return GuardTrack(
      booking: booking,
      guard: guard,
      reference: reference,
      profile: profile,
      ratings: ratings,
    );
  }

  /// The guard's latest position. 404 = no fix recorded yet · 403 = booking no longer active
  /// (presence IDOR gate) → both degrade to "no live position". Any OTHER API error is rethrown
  /// so the screen shows its retry body (this read is core to the map).
  Future<GuardLocation?> _fetchLocation(String guardId) async {
    try {
      final data =
          await ref.read(pguardApiProvider).get('/guards/$guardId/location');
      return GuardLocation.tryParse(data);
    } on ApiException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 403) rethrow;
      return null;
    }
  }

  /// The guard's public mini-profile (name + experience). Pure enrichment — on ANY API error
  /// (403 not-on-active-booking, 404 not-yet-approved, 5xx) it degrades to `null` and the card
  /// shows a generic role label. Never blocks the map.
  Future<GuardPublicProfile?> _fetchPublicProfile(String guardId) async {
    try {
      final data =
          await ref.read(pguardApiProvider).get('/guards/$guardId/public');
      return GuardPublicProfile.tryParse(data);
    } on ApiException {
      return null;
    }
  }

  /// The guard's visible ratings aggregate. Pure enrichment — degrades to `null` on any API
  /// error; the card then shows "no reviews yet" (never a fake 0.0).
  Future<GuardRatings?> _fetchRatings(String guardId) async {
    try {
      final data =
          await ref.read(pguardApiProvider).get('/guards/$guardId/ratings');
      if (data is! Map<String, dynamic>) return null;
      return GuardRatings.fromJson(data);
    } on ApiException {
      return null;
    }
  }

  /// One-shot, user-initiated re-pull (the refresh button) — a gesture, not a timer.
  /// Errors are NOT rethrown: the provider state already carries them for the UI, and the
  /// callers are fire-and-forget button handlers (a rethrow would only spam the error zone).
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // state is AsyncError — the screen renders the retry body from it.
    }
  }
}
