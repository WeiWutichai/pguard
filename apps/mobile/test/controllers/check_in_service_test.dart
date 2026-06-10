import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/media/photo_capture.dart';
import 'package:pguard_mobile/core/models/tracking.dart';
import 'package:pguard_mobile/core/network/api_client.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/network/check_in_service.dart';

import '../support/fakes.dart';

Map<String, dynamic> progressReportJson() => {
      'id': 'pr1',
      'booking_id': 'b1',
      'guard_id': 'g1',
      'hour_number': 1,
      'photo_key': 'booking/b1/checkins/x.jpg',
      'photo_url': 'http://minio:9000/booking/b1/checkins/x.jpg?sig=abc',
      'lat': 13.75,
      'lng': 100.5,
      'accuracy_m': 8.0,
      'note': 'perimeter clear',
      'created_at': '2026-06-10T00:00:00Z',
    };

void main() {
  late Directory tmp;
  late File photo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pguard_checkin_test');
    photo = File('${tmp.path}/checkpoint.jpg')
      ..writeAsBytesSync(List<int>.filled(64, 7));
  });

  tearDown(() => tmp.delete(recursive: true));

  CapturedPhoto capturedJpg() =>
      CapturedPhoto(path: photo.path, sizeBytes: 64);

  // ---------- request shape (golden) ----------

  group('FormData (golden — matches the merged contract)', () {
    test('sends hour_number + photo (single, declared MIME) + GPS + note', () async {
      FormData? sent;
      final api = FakeApi(onPost: (path, data) async {
        expect(path, '/bookings/b1/progress-reports');
        sent = data as FormData;
        return progressReportJson();
      });
      final service = ApiCheckInService(api: api);

      await service.submit(
        bookingId: 'b1',
        hourNumber: 3,
        photo: capturedJpg(),
        gps: GpsSample(
            lat: 13.75, lng: 100.5, accuracy: 8.0, recordedAt: DateTime(2026)),
        note: '  ตรวจรอบนอกเรียบร้อย  ',
      );

      final fields = {for (final f in sent!.fields) f.key: f.value};
      // contract field NAMES (not the stale message/files), values stringified for multipart.
      expect(fields['hour_number'], '3');
      expect(fields['lat'], '13.75');
      expect(fields['lng'], '100.5');
      expect(fields['accuracy'], '8.0');
      expect(fields['note'], 'ตรวจรอบนอกเรียบร้อย', reason: 'trimmed');
      expect(fields.containsKey('message'), isFalse, reason: 'no stale `message`');

      final file = sent!.files.single;
      expect(file.key, 'photo', reason: 'single `photo` part, not `files`');
      expect(file.value.filename, 'checkpoint.jpg');
      expect(
        '${file.value.contentType?.type}/${file.value.contentType?.subtype}',
        'image/jpeg',
      );
    });

    test('omits lat/lng/accuracy when no GPS, and note when empty', () async {
      FormData? sent;
      final api = FakeApi(onPost: (_, data) async {
        sent = data as FormData;
        return progressReportJson();
      });
      await ApiCheckInService(api: api).submit(
        bookingId: 'b1',
        hourNumber: 1,
        photo: capturedJpg(),
        note: '   ',
      );
      final keys = sent!.fields.map((f) => f.key).toSet();
      expect(keys, {'hour_number'});
      expect(keys.contains('lat'), isFalse);
      expect(keys.contains('note'), isFalse);
    });

    test('omits accuracy when GPS has none but keeps the lat/lng pair', () async {
      FormData? sent;
      final api = FakeApi(onPost: (_, data) async {
        sent = data as FormData;
        return progressReportJson();
      });
      await ApiCheckInService(api: api).submit(
        bookingId: 'b1',
        hourNumber: 1,
        photo: capturedJpg(),
        gps: GpsSample(lat: 1.0, lng: 2.0, recordedAt: DateTime(2026)),
      );
      final keys = sent!.fields.map((f) => f.key).toSet();
      expect(keys.containsAll(<String>{'lat', 'lng'}), isTrue);
      expect(keys.contains('accuracy'), isFalse);
    });

    test('rejects a non-image photo client-side (no upload attempt)', () async {
      final api = FakeApi(onPost: (_, __) async => fail('must not upload'));
      final service = ApiCheckInService(api: api);
      final mov = CapturedPhoto(path: '${tmp.path}/clip.mov', sizeBytes: 10);
      await expectLater(
        () => service.submit(bookingId: 'b1', hourNumber: 1, photo: mov),
        throwsA(isA<ApiException>()),
      );
      expect(api.calls, isEmpty);
    });
  });

  // ---------- error → UX mapping ----------

  group('error mapping', () {
    ApiCheckInService serviceThatThrows(ApiException e) =>
        ApiCheckInService(api: FakeApi(onPost: (_, __) async => throw e));

    test('409 duplicate-hour is ABSORBED as success (idempotent retry)', () async {
      final service = serviceThatThrows(const ApiException(
          message: 'A check-in for hour 1 already exists', statusCode: 409));
      // Completes without throwing → the controller marks the slot done.
      await service.submit(
          bookingId: 'b1', hourNumber: 1, photo: capturedJpg());
    });

    test('409 too-early surfaces a bilingual "not time yet" message', () async {
      final service = serviceThatThrows(const ApiException(
          message: 'Too early to check in for hour 3', statusCode: 409));
      await expectLater(
        () => service.submit(
            bookingId: 'b1', hourNumber: 3, photo: capturedJpg()),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', contains('ยังไม่ถึงเวลา'))
              .having((e) => e.message, 'message',
                  contains('not time for this check-in')),
        ),
      );
    });

    test('413 surfaces a bilingual "photo too large" message', () async {
      final service = serviceThatThrows(
          const ApiException(message: 'Request body too large', statusCode: 413));
      await expectLater(
        () => service.submit(
            bookingId: 'b1', hourNumber: 1, photo: capturedJpg()),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 413)
            .having((e) => e.message, 'message', contains('รูปภาพใหญ่เกินไป'))
            .having((e) => e.message, 'message', contains('too large'))),
      );
    });

    test('403/404 surface a bilingual "can\'t check in for this job" message',
        () async {
      for (final code in [403, 404]) {
        final service = serviceThatThrows(
            ApiException(message: 'Forbidden', statusCode: code));
        await expectLater(
          () => service.submit(
              bookingId: 'b1', hourNumber: 1, photo: capturedJpg()),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', code)
              .having((e) => e.message, 'message', contains('เช็คอินงานนี้ไม่ได้'))),
        );
      }
    });

    test('network failure surfaces a bilingual retry-safe message', () async {
      final service = serviceThatThrows(const ApiException(
          message: 'Network error — please check your connection'));
      await expectLater(
        () => service.submit(
            bookingId: 'b1', hourNumber: 1, photo: capturedJpg()),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetwork, 'isNetwork', isTrue)
            .having((e) => e.message, 'message', contains('ส่งใหม่ได้เลย'))),
      );
    });
  });

  // ---------- multipart upload integrates with the token-refresh machinery ----------
  //
  // The real mechanism that protects an upload from a stale token is the PROACTIVE refresh in
  // `ApiClient._onRequest`: an expiring/expired access token is refreshed BEFORE the request is
  // sent, so the multipart body goes out once, with a fresh Bearer. (The reactive `_onError`
  // 401-retry — which holds the `FormData.clone` — is effectively unreachable for an HTTP 401
  // RESPONSE: `validateStatus: (s) => s < 500` makes a 401 a normal response, not a
  // `DioException`, so `_onError` never fires. That's a pre-existing api_client property, noted
  // for follow-up — out of scope here.) This test exercises the path that actually runs.

  test('multipart check-in is sent with a proactively-refreshed token', () async {
    final store = InMemoryStore()
      ..access = fakeJwt({'exp': 1000000000}) // expired (2001) → proactive refresh fires
      ..refresh = 'r1';

    var refreshHits = 0;
    String? sentAuth;
    final freshAccess = fakeJwt({'exp': 9999999999});
    final adapter = _StubAdapter((options) async {
      if (options.path == '/auth/refresh') {
        refreshHits++;
        return _json(200, {
          'success': true,
          'data': {'access_token': freshAccess, 'refresh_token': 'r2'},
        });
      }
      if (options.path == '/bookings/b1/progress-reports') {
        sentAuth = options.headers['Authorization']?.toString();
        return _json(200, {'success': true, 'data': progressReportJson()});
      }
      return _json(404, {'success': false, 'error': 'not found'});
    });

    final api = ApiClient(
      store: store,
      dio: Dio()..httpClientAdapter = adapter,
      refreshDio: Dio()..httpClientAdapter = adapter,
    );

    // Must NOT throw: the expired token is refreshed before the multipart POST is sent.
    await ApiCheckInService(api: api)
        .submit(bookingId: 'b1', hourNumber: 1, photo: capturedJpg());

    expect(refreshHits, 1, reason: 'the expired token was refreshed before sending');
    expect(sentAuth, 'Bearer $freshAccess', reason: 'upload carried the fresh token');
    expect(store.access, freshAccess);
  });
}

/// A scriptable [HttpClientAdapter] — routes by request path. Lets the 401-retry test exercise
/// the REAL [ApiClient] interceptor (incl. its FormData.clone) without a network or mock package.
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
