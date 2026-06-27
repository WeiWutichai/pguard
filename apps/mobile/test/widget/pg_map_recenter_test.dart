import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/features/booking/widgets/pg_map.dart';

/// A two-point set the camera frames on open (the guard + destination of a nav route).
const _a = GeoPoint(13.7563, 100.5018);
const _b = GeoPoint(13.8000, 100.6000);

/// A live point well away from both [_a]/[_b] so a "did the camera centre on it" assertion is
/// unambiguous (it is NOT the midpoint the fit-all mode would land on).
const _live = GeoPoint(13.7563, 100.5018);
const _liveMoved = GeoPoint(13.7610, 100.5090);

/// Read the (internal) [MapController] PgMap renders with so a test can inspect [MapController.camera].
MapController _controllerOf(WidgetTester tester) =>
    tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

/// Pump the FIT-ALL variant (no `follow`) over the fixed two-point route, settle layout so
/// `onMapReady` / the first size-change fire, and return the live [MapController].
Future<MapController> pumpFitAll(WidgetTester tester, int token) async {
  await _pumpFitAll(tester, token);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return _controllerOf(tester);
}

Future<void> _pumpFitAll(WidgetTester tester, int token) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
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
    ),
  );
}

/// Pump the LIVE-FOLLOW variant — [follow] is the live point, [token] the recenter trigger.
Future<MapController> pumpFollow(
  WidgetTester tester, {
  required GeoPoint follow,
  int token = 0,
}) async {
  await _pumpFollow(tester, follow: follow, token: token);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return _controllerOf(tester);
}

Future<void> _pumpFollow(
  WidgetTester tester, {
  required GeoPoint follow,
  required int token,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: PgMap(
              recenterToken: token,
              interactive: true,
              follow: follow,
              followZoom: 16,
              polyline: PgPolyline(points: [follow, _b]),
              markers: [
                PgMarker(point: follow, child: const Icon(Icons.shield)),
                const PgMarker(point: _b, child: Icon(Icons.place)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('fit-all mode (no follow — the booking picker / route overview)', () {
    testWidgets(
        'on open the camera frames the WHOLE route (both polyline points)',
        (tester) async {
      final controller = await pumpFitAll(tester, 0);

      final centre = controller.camera.center;
      final midLat = (_a.lat + _b.lat) / 2;
      final midLng = (_a.lng + _b.lng) / 2;
      expect(centre.latitude, closeTo(midLat, 0.02));
      expect(centre.longitude, closeTo(midLng, 0.02));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'bumping recenterToken re-fits the camera after the user panned away',
        (tester) async {
      final controller = await pumpFitAll(tester, 0);
      final framed = controller.camera.center;

      controller.move(const LatLng(15.0, 102.0), 8);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.camera.center.latitude,
          isNot(closeTo(framed.latitude, 0.1)),
          reason: 'precondition: the camera really moved off the route');

      // Bump the token — coordinates UNCHANGED, so only the token can trigger the re-fit.
      await _pumpFitAll(tester, 1);
      await tester.pump(const Duration(milliseconds: 50));

      final recentred = controller.camera.center;
      expect(recentred.latitude, closeTo(framed.latitude, 0.02),
          reason: 'a recenterToken bump re-frames the route');
      expect(recentred.longitude, closeTo(framed.longitude, 0.02));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an UNCHANGED token + unchanged points does NOT re-fit',
        (tester) async {
      final controller = await pumpFitAll(tester, 3);

      controller.move(const LatLng(15.0, 102.0), 8);
      await tester.pump(const Duration(milliseconds: 50));
      final pannedAway = controller.camera.center;

      await _pumpFitAll(tester, 3);
      await tester.pump(const Duration(milliseconds: 50));

      final after = controller.camera.center;
      expect(after.latitude, closeTo(pannedAway.latitude, 1e-6),
          reason: 'same token + same points → no re-fit');
      expect(after.longitude, closeTo(pannedAway.longitude, 1e-6));

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('live-follow mode (guard nav self / customer guard-tracking)', () {
    testWidgets(
        'on open the camera CENTRES on the live point at nav zoom (NOT the whole route)',
        (tester) async {
      final controller = await pumpFollow(tester, follow: _live);

      final centre = controller.camera.center;
      expect(centre.latitude, closeTo(_live.lat, 1e-4),
          reason: 'the camera sits on the live point, not the route midpoint');
      expect(centre.longitude, closeTo(_live.lng, 1e-4));
      expect(controller.camera.zoom, closeTo(16, 0.01),
          reason: 'it holds the navigation zoom, not a zoomed-out route fit');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'a live-point update re-centres the camera on the new point (it FOLLOWS)',
        (tester) async {
      final controller = await pumpFollow(tester, follow: _live);
      expect(controller.camera.center.latitude, closeTo(_live.lat, 1e-4));

      // The live fix advances — PgMap is UPDATED (not re-keyed), so didUpdateWidget follows it.
      await _pumpFollow(tester, follow: _liveMoved, token: 0);
      await tester.pump(const Duration(milliseconds: 50));

      final centre = controller.camera.center;
      expect(centre.latitude, closeTo(_liveMoved.lat, 1e-4),
          reason: 'the camera followed the live point to its new position');
      expect(centre.longitude, closeTo(_liveMoved.lng, 1e-4));
      expect(controller.camera.zoom, closeTo(16, 0.01),
          reason: 'still at the nav zoom while following');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'a MANUAL pan pauses follow: a later live update does NOT yank the camera back',
        (tester) async {
      final controller = await pumpFollow(tester, follow: _live);

      // The user pans away — emulate a real gesture-sourced move so onPositionChanged reports
      // hasGesture == true (which is what pauses auto-follow).
      (controller as MapControllerImpl).moveRaw(
        const LatLng(15.0, 102.0),
        9,
        hasGesture: true,
        source: MapEventSource.onDrag,
      );
      await tester.pump(const Duration(milliseconds: 50));
      final pannedTo = controller.camera.center;
      expect(pannedTo.latitude, closeTo(15.0, 0.01),
          reason:
              'precondition: the user panned the camera off the live point');

      // A fresh live fix arrives — because the user paused follow, the camera must STAY put.
      await _pumpFollow(tester, follow: _liveMoved, token: 0);
      await tester.pump(const Duration(milliseconds: 50));

      final after = controller.camera.center;
      expect(after.latitude, closeTo(pannedTo.latitude, 1e-4),
          reason:
              'auto-follow is paused — a live update must not override the manual pan');
      expect(after.longitude, closeTo(pannedTo.longitude, 1e-4));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the recenter token RE-ENGAGES follow after a manual pan',
        (tester) async {
      final controller = await pumpFollow(tester, follow: _live, token: 0);

      // Pan away (pauses follow).
      (controller as MapControllerImpl).moveRaw(
        const LatLng(15.0, 102.0),
        9,
        hasGesture: true,
        source: MapEventSource.onDrag,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.camera.center.latitude, closeTo(15.0, 0.01));

      // Tap recenter (bump the token) with the live point at _liveMoved — it must snap back ONTO
      // the live point at nav zoom AND re-engage follow.
      await _pumpFollow(tester, follow: _liveMoved, token: 1);
      await tester.pump(const Duration(milliseconds: 50));

      final recentred = controller.camera.center;
      expect(recentred.latitude, closeTo(_liveMoved.lat, 1e-4),
          reason: 'the recenter snaps the camera back onto the live point');
      expect(recentred.longitude, closeTo(_liveMoved.lng, 1e-4));
      expect(controller.camera.zoom, closeTo(16, 0.01));

      // Follow re-engaged: the NEXT live update is followed again (no second recenter needed).
      await _pumpFollow(tester, follow: _live, token: 1);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.camera.center.latitude, closeTo(_live.lat, 1e-4),
          reason:
              'follow re-engaged by the recenter — the next fix is tracked');

      await tester.pumpWidget(const SizedBox());
    });
  });
}
