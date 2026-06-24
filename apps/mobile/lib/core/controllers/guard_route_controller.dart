import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../location/routing_service.dart';
import '../models/geo.dart';
import '../providers.dart';

part 'guard_route_controller.g.dart';

/// Quantise an origin coordinate to a ~100 m grid so the route provider's family key only changes
/// when the guard has moved MEANINGFULLY — not on every GPS tick. The movement-gated GPS stream
/// already emits ~15 m fixes; without this each fix would be a distinct family key and trigger a
/// fresh OSRM request. At Thailand's latitude 0.001° ≈ 111 m (lat) / ≈ 108 m (lng), so rounding to
/// 3 decimals snaps to roughly a 100 m cell. The destination is a fixed booking pin, so it is
/// rounded with more precision (5 dp ≈ 1 m) to stay accurate while still keying the cache.
///
/// Result: the same (origin-cell, dest) pair reuses ONE cached [RouteResult] across the full-screen
/// nav map AND the inline preview — a re-fetch happens only when the guard crosses into a new ~100 m
/// cell or the destination changes. Pure (no I/O) so the snapping is unit-testable.
GeoPoint snapOrigin(GeoPoint p) => GeoPoint(
      (p.lat * 1000).round() / 1000,
      (p.lng * 1000).round() / 1000,
    );

/// Round a destination coordinate for the cache key (5 dp ≈ 1 m). Pure.
GeoPoint snapDest(GeoPoint p) => GeoPoint(
      (p.lat * 100000).round() / 100000,
      (p.lng * 100000).round() / 100000,
    );

/// The REAL road route for the guard navigation map, keyed by the (snapped) origin + destination.
///
/// Riverpod caches one [RouteResult] per family key, so the full-screen [GuardNavigationScreen] map
/// and the inline [TravelMapPreview] that watch the SAME origin/dest share a single OSRM fetch (no
/// per-rebuild re-fetch from the tiny preview). Auto-disposes when nothing watches the key.
///
/// DEBOUNCE / re-fetch policy: callers pass the guard's live origin through [snapOrigin] before
/// watching, so a fresh fetch fires only when the guard moves into a new ~100 m cell (or the dest
/// changes) — never on each ~15 m GPS tick. Returns null when [RoutingService] could not produce a
/// route (offline / OSRM down / no route); the caller then DEGRADES to the straight-line estimate.
// NOTE: the parameters are named `start`/`end`, NOT `origin`/`dest`/`from`/`to` — riverpod_generator
// turns each family parameter into a getter/named-arg in the generated code, and several names are
// RESERVED there: `origin` clashes with `ProviderElementBase.origin`, and `from` clashes with the
// generator's own internal `from:` argument (a duplicated-named-argument compile error). `start`/
// `end` are collision-free; the underlying [RoutingService] still receives them as origin/dest.
@riverpod
Future<RouteResult?> guardRoute(
  GuardRouteRef ref, {
  required GeoPoint start,
  required GeoPoint end,
}) async {
  final service = ref.watch(routingServiceProvider);
  return service.route(origin: start, dest: end);
}
