import 'dart:async';

import '../location/place_search_service.dart';

/// Debounced place-search driver — the testable logic behind `PlaceSearchField`, kept out of the
/// widget so the debounce + race-safety can be unit-tested without pumping a widget.
///
/// Honours Nominatim's usage policy from the CLIENT side: a 500 ms debounce coalesces keystrokes
/// (no per-keystroke request), and only the LATEST query's results are ever surfaced — if the user
/// keeps typing while a request is in flight, the stale response is dropped (so the dropdown never
/// shows results for an old query). Short queries (< [minChars]) clear results without a request.
///
/// The widget calls [onQueryChanged] on each keystroke and listens to [results]/[loading]; it
/// must call [dispose] to cancel the pending timer.
class PlaceSearchController {
  PlaceSearchController({
    required this.service,
    this.debounce = const Duration(milliseconds: 500),
    this.minChars = 3,
  });

  final PlaceSearchService service;
  final Duration debounce;
  final int minChars;

  final _results = StreamController<List<PlaceResult>>.broadcast();
  final _loading = StreamController<bool>.broadcast();

  /// The latest result list (emitted after each settled, non-stale search).
  Stream<List<PlaceResult>> get results => _results.stream;

  /// Whether a debounced search is pending/in flight (drives a spinner in the field).
  Stream<bool> get loading => _loading.stream;

  Timer? _timer;

  /// Monotonic request id — only the most-recent search is allowed to publish, so an out-of-order
  /// (slow) response for an earlier query is discarded.
  int _seq = 0;
  bool _disposed = false;

  /// Feed a new query (typically the text field's current value). Resets the debounce timer; an
  /// empty/too-short query clears results immediately and cancels any pending search.
  void onQueryChanged(String query) {
    if (_disposed) return;
    _timer?.cancel();
    final q = query.trim();
    if (q.length < minChars) {
      _seq++; // invalidate any in-flight search so its late result can't land
      _emitLoading(false);
      _emitResults(const []);
      return;
    }
    _emitLoading(true);
    _timer = Timer(debounce, () => _run(q));
  }

  Future<void> _run(String query) async {
    final mine = ++_seq;
    final hits = await service.search(query);
    if (_disposed || mine != _seq) return; // a newer query superseded this one
    _emitLoading(false);
    _emitResults(hits);
  }

  void _emitResults(List<PlaceResult> r) {
    if (!_disposed && !_results.isClosed) _results.add(r);
  }

  void _emitLoading(bool v) {
    if (!_disposed && !_loading.isClosed) _loading.add(v);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _results.close();
    _loading.close();
  }
}
