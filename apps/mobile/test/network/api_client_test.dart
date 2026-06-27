import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/network/api_client.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';

import '../support/fakes.dart';

/// The reactive 401 refresh+retry (`_onError`) is now LIVE: `validateStatus` excludes 401, so a
/// 401 becomes a DioException that reaches the interceptor. These tests pin that behaviour (incl.
/// the FormData.clone path) and confirm the no-refresh case is unchanged.
void main() {
  const farFuture = 9999999999; // exp far ahead → no PROACTIVE refresh in _onRequest

  ApiClient buildClient(InMemoryStore store, HttpClientAdapter adapter) =>
      ApiClient(
        store: store,
        dio: Dio()..httpClientAdapter = adapter,
        refreshDio: Dio()..httpClientAdapter = adapter,
      );

  test('a 401 with a working refresh is transparently refreshed + retried (GET)',
      () async {
    final store = InMemoryStore()
      ..access = fakeJwt({'exp': farFuture})
      ..refresh = 'r1';
    var hits = 0;
    var refreshes = 0;
    final adapter = _StubAdapter((options) async {
      if (options.path == '/auth/refresh') {
        refreshes++;
        return _json(200, {
          'success': true,
          'data': {'access_token': fakeJwt({'exp': farFuture}), 'refresh_token': 'r2'},
        });
      }
      if (options.path == '/bookings/b1') {
        hits++;
        return hits == 1
            ? _json(401, {'success': false, 'error': {'code': 'UNAUTHORIZED', 'message': 'revoked'}})
            : _json(200, {'success': true, 'data': {'id': 'b1'}});
      }
      return _json(404, {'success': false, 'error': 'nope'});
    });

    final data = await buildClient(store, adapter).get('/bookings/b1');

    expect(refreshes, 1);
    expect(hits, 2, reason: 'original 401 then a retry');
    expect((data as Map)['id'], 'b1');
    expect(store.access, isNot('r1'));
  });

  test('a 401 on a multipart POST survives the retry via FormData.clone', () async {
    final store = InMemoryStore()
      ..access = fakeJwt({'exp': farFuture})
      ..refresh = 'r1';
    var hits = 0;
    final adapter = _StubAdapter((options) async {
      if (options.path == '/auth/refresh') {
        return _json(200, {
          'success': true,
          'data': {'access_token': fakeJwt({'exp': farFuture}), 'refresh_token': 'r2'},
        });
      }
      if (options.path == '/attachments') {
        hits++;
        // A finalized FormData re-sent WITHOUT cloning would throw a StateError before reaching
        // here a second time; getting two hits + a 200 proves the clone worked.
        return hits == 1
            ? _json(401, {'success': false, 'error': {'code': 'UNAUTHORIZED', 'message': 'revoked'}})
            : _json(200, {'success': true, 'data': {'id': 'att1'}});
      }
      return _json(404, {'success': false, 'error': 'nope'});
    });

    final form = FormData.fromMap({'k': 'v'});
    final data = await buildClient(store, adapter).post('/attachments', data: form);

    expect(hits, 2, reason: 'multipart retried with a cloned body');
    expect((data as Map)['id'], 'att1');
  });

  test('a 401 with no usable refresh still surfaces as ApiException(401)', () async {
    final store = InMemoryStore()..access = fakeJwt({'exp': farFuture}); // no refresh token
    // No refresh token → _doRefresh returns null without ever hitting /auth/refresh.
    final adapter = _StubAdapter((options) async => _json(
        401, {'success': false, 'error': {'code': 'UNAUTHORIZED', 'message': 'revoked'}}));

    await expectLater(
      () => buildClient(store, adapter).get('/bookings/b1'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
  });

  test('a retry that ALSO 401s surfaces ApiException(401) — no infinite loop', () async {
    final store = InMemoryStore()
      ..access = fakeJwt({'exp': farFuture})
      ..refresh = 'r1';
    var hits = 0;
    final adapter = _StubAdapter((options) async {
      if (options.path == '/auth/refresh') {
        return _json(200, {
          'success': true,
          'data': {'access_token': fakeJwt({'exp': farFuture}), 'refresh_token': 'r2'},
        });
      }
      hits++;
      // Refresh succeeds, but the resource keeps returning 401 (e.g. a permission, not a token,
      // problem). The pg_retried guard must stop after exactly one retry.
      return _json(401, {'success': false, 'error': {'code': 'UNAUTHORIZED', 'message': 'revoked'}});
    });

    await expectLater(
      () => buildClient(store, adapter).get('/bookings/b1'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(hits, 2, reason: 'original + exactly one retry, then it gives up');
  });

  // A refresh that fails for a TRANSIENT reason (identity restarting during a deploy, a flaky
  // network → 5xx/no-response) must NOT log the user out — the refresh token is still valid. Only a
  // genuine rejection of the refresh token itself (401/403: invalid / expired / reuse-detected)
  // drops the session. (Regression: both devices logged out during a deploy despite valid 7-day
  // refresh tokens, because ANY DioException cleared the session.)
  for (final c in [
    (status: 503, lost: false), // identity restarting
    (status: 502, lost: false), // bad gateway
    (status: 500, lost: false), // upstream blip
    (status: 401, lost: true), // refresh token rejected
    (status: 403, lost: true), // refresh token rejected
  ]) {
    test('refresh ${c.status} → sessionLost=${c.lost}', () async {
      final store = InMemoryStore()
        ..access = fakeJwt({'exp': 1}) // expired → proactive refresh fires first
        ..refresh = 'r1';
      var authLost = false;
      final adapter = _StubAdapter((options) async {
        if (options.path == '/auth/refresh') {
          return _json(c.status, {'success': false, 'error': 'x'});
        }
        return _json(200, {'success': true, 'data': {'ok': true}});
      });
      final client = ApiClient(
        store: store,
        dio: Dio()..httpClientAdapter = adapter,
        refreshDio: Dio()..httpClientAdapter = adapter,
        onAuthLost: () => authLost = true,
      );
      try {
        await client.get('/bookings/b1');
      } catch (_) {}
      expect(authLost, c.lost);
      // The refresh token is preserved on a transient failure, cleared on a genuine rejection.
      expect(store.refresh, c.lost ? isNull : 'r1');
    });
  }
}

/// A scriptable [HttpClientAdapter] routed by request path.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
