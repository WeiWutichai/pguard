import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/place_search_controller.dart';
import 'package:pguard_mobile/core/location/place_search_service.dart';
import 'package:pguard_mobile/core/models/geo.dart';

/// A scriptable [PlaceSearchService]: records every query and returns a canned result list per
/// query (with an optional artificial latency to simulate a slow, out-of-order response).
class _FakeSearch implements PlaceSearchService {
  _FakeSearch();

  final List<String> queries = [];
  Map<String, List<PlaceResult>> answers = {};
  Map<String, Duration> latency = {};

  PlaceResult _hit(String name) =>
      PlaceResult(displayName: name, point: const GeoPoint(13.0, 100.0));

  @override
  Future<List<PlaceResult>> search(String query) async {
    queries.add(query);
    final delay = latency[query] ?? Duration.zero;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return answers[query] ?? [_hit('result for $query')];
  }

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

void main() {
  group('PlaceSearchController debounce', () {
    test('coalesces rapid keystrokes into ONE request after the debounce', () {
      fakeAsync((async) {
        final svc = _FakeSearch();
        final ctrl = PlaceSearchController(service: svc);
        addTearDown(ctrl.dispose);

        // Type "cafe" one char at a time, faster than the debounce.
        ctrl.onQueryChanged('c');
        async.elapse(const Duration(milliseconds: 100));
        ctrl.onQueryChanged('ca');
        async.elapse(const Duration(milliseconds: 100));
        ctrl.onQueryChanged('caf');
        async.elapse(const Duration(milliseconds: 100));
        ctrl.onQueryChanged('cafe');
        // Nothing fired yet (still inside the 500ms window from the last keystroke).
        expect(svc.queries, isEmpty);

        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        // Exactly one request, for the FINAL query.
        expect(svc.queries, ['cafe']);
      });
    });

    test('short / empty queries clear results without a request', () {
      fakeAsync((async) {
        final svc = _FakeSearch();
        final ctrl = PlaceSearchController(service: svc, minChars: 3);
        addTearDown(ctrl.dispose);

        final emitted = <List<PlaceResult>>[];
        ctrl.results.listen(emitted.add);

        ctrl.onQueryChanged('ab'); // below minChars
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(svc.queries, isEmpty, reason: 'no request below minChars');
        expect(emitted, isNotEmpty);
        expect(emitted.last, isEmpty, reason: 'results cleared');
      });
    });

    test('only the LATEST query publishes — a stale slow response is dropped', () {
      fakeAsync((async) {
        final svc = _FakeSearch()
          // "old" is slow (1s); "new" is instant — "new" must win even though "old" was issued
          // first and lands later.
          ..latency['old'] = const Duration(seconds: 1)
          ..answers['old'] = const [
            PlaceResult(displayName: 'OLD', point: GeoPoint(0, 0))
          ]
          ..answers['new'] = const [
            PlaceResult(displayName: 'NEW', point: GeoPoint(1, 1))
          ];
        final ctrl = PlaceSearchController(service: svc);
        addTearDown(ctrl.dispose);

        final emitted = <List<PlaceResult>>[];
        ctrl.results.listen(emitted.add);

        ctrl.onQueryChanged('old');
        async.elapse(const Duration(milliseconds: 500)); // debounce fires → "old" search starts
        ctrl.onQueryChanged('new');
        async.elapse(const Duration(milliseconds: 500)); // debounce fires → "new" search starts
        async.flushMicrotasks(); // "new" resolves (instant)
        async.elapse(const Duration(seconds: 1)); // "old" finally resolves
        async.flushMicrotasks();

        final names =
            emitted.where((e) => e.isNotEmpty).map((e) => e.single.displayName);
        expect(names, contains('NEW'));
        expect(names, isNot(contains('OLD')),
            reason: 'the superseded query must not publish');
        // The last non-empty emission is the current query's result.
        expect(emitted.where((e) => e.isNotEmpty).last.single.displayName, 'NEW');
      });
    });

    test('loading toggles true on debounce-start, false on settle', () {
      fakeAsync((async) {
        final svc = _FakeSearch();
        final ctrl = PlaceSearchController(service: svc);
        addTearDown(ctrl.dispose);

        final loading = <bool>[];
        ctrl.loading.listen(loading.add);

        ctrl.onQueryChanged('cafe');
        async.flushMicrotasks();
        expect(loading.last, isTrue, reason: 'spinner on while debouncing');

        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(loading.last, isFalse, reason: 'spinner off once results land');
      });
    });
  });
}
