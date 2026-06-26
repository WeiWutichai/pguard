import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/features/booking/widgets/pg_map.dart';

/// A two-point set the camera frames on open (the guard + destination of a nav route).
const _a = GeoPoint(13.7563, 100.5018);
const _b = GeoPoint(13.8000, 100.6000);

/// Pump a [PgMap] with [token] over the fixed two-point [PgPolyline] route, give flutter_map a
/// concrete size + time to lay out / fire `onMapReady`, and return the (internal) [MapController]
/// the map renders with so a test can read the live [MapController.camera].
Future<MapController> pumpMap(WidgetTester tester, int token) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: PgMap(
            recenterToken: token,
            interactive: true,
            polyline: const PgPolyline(points: [_a, _b]),
          ),
        ),
      ),
    ),
  );
  // Let the tiles/camera settle and `onMapReady` fire so `controller.camera` is valid.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
}

/// Rebuild the SAME PgMap subtree with a (possibly new) [token] — flutter_map's single map +
/// MapController persist (no re-key), exercising [PgMap.didUpdateWidget].
Future<void> rebuildWithToken(WidgetTester tester, int token) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: PgMap(
            recenterToken: token,
            interactive: true,
            polyline: const PgPolyline(points: [_a, _b]),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('on open the camera frames the WHOLE route (both polyline points)',
      (tester) async {
    final controller = await pumpMap(tester, 0);

    // The fit centre sits between the two route points (it frames both, not one) — proves the
    // polyline points feed the on-open auto-fit, not just markers.
    final centre = controller.camera.center;
    final midLat = (_a.lat + _b.lat) / 2;
    final midLng = (_a.lng + _b.lng) / 2;
    expect(centre.latitude, closeTo(midLat, 0.02));
    expect(centre.longitude, closeTo(midLng, 0.02));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bumping recenterToken re-fits the camera after the user panned away',
      (tester) async {
    final controller = await pumpMap(tester, 0);
    final framed = controller.camera.center;

    // Simulate the user panning + zooming away — the camera now sits far off the route.
    controller.move(const LatLng(15.0, 102.0), 8);
    await tester.pump(const Duration(milliseconds: 50));
    final pannedAway = controller.camera.center;
    expect(pannedAway.latitude, isNot(closeTo(framed.latitude, 0.1)),
        reason: 'precondition: the camera really moved off the route');

    // Bump the token — coordinates are UNCHANGED, so only the token can trigger the re-fit.
    await rebuildWithToken(tester, 1);

    final recentred = controller.camera.center;
    expect(recentred.latitude, closeTo(framed.latitude, 0.02),
        reason: 'a recenterToken bump re-frames the route');
    expect(recentred.longitude, closeTo(framed.longitude, 0.02));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'an UNCHANGED token + unchanged points does NOT re-fit (no-op rebuild stays put)',
      (tester) async {
    final controller = await pumpMap(tester, 3);

    // Pan away, then rebuild with the SAME token + SAME points: the no-op-rebuild guard must hold,
    // so the camera stays where the user left it.
    controller.move(const LatLng(15.0, 102.0), 8);
    await tester.pump(const Duration(milliseconds: 50));
    final pannedAway = controller.camera.center;

    await rebuildWithToken(tester, 3);

    final after = controller.camera.center;
    expect(after.latitude, closeTo(pannedAway.latitude, 1e-6),
        reason: 'same token + same points → no re-fit');
    expect(after.longitude, closeTo(pannedAway.longitude, 1e-6));

    await tester.pumpWidget(const SizedBox());
  });
}
