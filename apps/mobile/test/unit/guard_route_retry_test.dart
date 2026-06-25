import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/guard_route_controller.dart';
import 'package:pguard_mobile/core/location/routing_service.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/core/providers.dart';

/// A scriptable [RoutingService]: returns null (a routing failure) for the first [failTimes] calls,
/// then a fixed route. Counts calls so the test can assert the retry actually re-hit the service.
class _ScriptedRouting implements RoutingService {
  _ScriptedRouting({required this.failTimes});

  final int failTimes;
  int calls = 0;

  static final _route = RouteResult.fromOsrm({
    'routes': [
      {
        'distance': 1000.0,
        'duration': 120.0,
        'geometry': {
          'coordinates': [
            [100.5018, 13.7563],
            [100.5331, 13.7367],
          ],
        },
      },
    ],
  });

  @override
  Future<RouteResult?> route(
      {required GeoPoint origin, required GeoPoint dest}) async {
    calls++;
    if (calls <= failTimes) return null;
    return _route;
  }
}

void main() {
  const start = GeoPoint(13.756, 100.502);
  const end = GeoPoint(13.73670, 100.53310);

  test('a null (failed) route self-invalidates and recovers once routing returns a route', () {
    fakeAsync((async) {
      final routing = _ScriptedRouting(failTimes: 1); // first call fails, then succeeds
      final container = ProviderContainer(
        overrides: [routingServiceProvider.overrideWithValue(routing)],
      );
      addTearDown(container.dispose);

      // Keep the provider alive (otherwise AutoDispose would tear it down before the retry).
      final sub = container.listen(
        guardRouteProvider(start: start, end: end),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // First fetch resolves to null (failure).
      async.flushMicrotasks();
      expect(routing.calls, 1);
      expect(sub.read().value, isNull);

      // Before the retry delay nothing re-fetches.
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(routing.calls, 1);

      // After the retry delay the provider self-invalidates and re-fetches — now it succeeds.
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(routing.calls, 2, reason: 'should have retried after the delay');
      expect(sub.read().value, isNotNull, reason: 'route should recover after retry');
    });
  });

  test('a successful route does NOT re-arm the retry timer (no busy re-fetch loop)', () {
    fakeAsync((async) {
      final routing = _ScriptedRouting(failTimes: 0); // succeeds immediately
      final container = ProviderContainer(
        overrides: [routingServiceProvider.overrideWithValue(routing)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        guardRouteProvider(start: start, end: end),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      async.flushMicrotasks();
      expect(routing.calls, 1);
      expect(sub.read().value, isNotNull);

      // Let plenty of time pass: a success must not schedule any further fetch.
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(routing.calls, 1, reason: 'a success must not loop');
    });
  });
}
