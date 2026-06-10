import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/booking.dart';
import '../models/geo.dart';
import '../models/tracking.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'booking_status_controller.dart';

part 'guard_location_controller.g.dart';

/// Everything the customer live-map renders, in one watchable state (the screen watches THIS
/// controller and nothing else).
class GuardTrack {
  const GuardTrack({required this.booking, this.guard, this.reference});

  /// The live booking (status drives the en-route/arrived chip + map availability).
  final Booking booking;

  /// The guard's latest fix — `null` when no guard is assigned yet, no fix is recorded (404),
  /// or the booking is no longer active so presence denies the read (403).
  final GuardLocation? guard;

  /// The customer's own device fix, shown as a reference marker. The v2 booking contract
  /// carries NO lat/lng (free-text `address` only — see `geo.dart`), so the device position is
  /// the best available stand-in for "where the guard is heading". `null` without a GPS fix.
  final GeoPoint? reference;

  BookingStatus get status => booking.status;
  String? get guardId => booking.guardId;

  /// Straight-line metres between guard and the reference point (`null` when either is unknown).
  double? get distanceFromReference {
    final g = guard;
    final r = reference;
    if (g == null || r == null) return null;
    return distanceMeters(g.point, r);
  }
}

/// Customer live-map controller — Phase 2 rules apply: there is NO location stream readable by
/// customers (`/ws/track` is guard-only GPS ingest, and booking events carry no lat/lng — see
/// `contracts/openapi/presence.yaml` + `contracts/asyncapi/events.yaml`), and `Timer.periodic`
/// polling is forbidden. So this controller WATCHES the booking-status controller: every status
/// frame pushed over the booking WebSocket (`guard_en_route`, `arrived`, …) re-runs [build],
/// which re-pulls ONE `GET /v1/guards/{id}/location` snapshot. Opening the screen and the
/// user-initiated [refresh] are the only other fetch triggers — every fetch in this path is
/// event- or gesture-driven, never a timer.
@riverpod
class GuardLocationController extends _$GuardLocationController {
  @override
  Future<GuardTrack> build(String bookingId) async {
    // Rebuilds on every pushed status event (the WS is owned by BookingStatusController, whose
    // ref.onDispose closes it — nothing to clean up here).
    final booking =
        await ref.watch(bookingStatusControllerProvider(bookingId).future);

    GuardLocation? guard;
    final guardId = booking.guardId;
    if (guardId != null) {
      try {
        final data =
            await ref.read(pguardApiProvider).get('/guards/$guardId/location');
        guard = GuardLocation.tryParse(data);
      } on ApiException catch (e) {
        // 404 = no fix recorded yet · 403 = booking no longer active (presence IDOR gate).
        // Both degrade to "no live position" — the map still shows status + address.
        if (e.statusCode != 404 && e.statusCode != 403) rethrow;
      }
    }

    // One-shot device fix for the reference marker (injectable; null when GPS is unavailable).
    final reference = await ref.read(locationServiceProvider).currentLocation();

    return GuardTrack(booking: booking, guard: guard, reference: reference);
  }

  /// One-shot, user-initiated re-pull (the refresh button) — a gesture, not a timer.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
