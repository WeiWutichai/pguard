import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/customer_avatar_controller.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  // A real temp JPEG so the upload's MultipartFile.fromFile() can stat/read it.
  late File tempImage;
  setUp(() async {
    tempImage = File(
        '${Directory.systemTemp.path}/pg_cust_avatar_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tempImage.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  });
  tearDown(() async {
    if (await tempImage.exists()) await tempImage.delete();
  });

  // The controller resolves its customer id from the SESSION (perf-review #3 — no `/auth/me` round
  // trip), so seed an authenticated customer `c1` rather than stubbing `/auth/me`.
  ProviderContainer container(FakeApi api, {Override? session}) {
    final c = ProviderContainer(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        session ?? seededCustomerSession(),
      ],
    );
    addTearDown(c.dispose);
    // autoDispose — keep alive across awaits.
    c.listen(customerAvatarControllerProvider, (_, __) {});
    return c;
  }

  test(
      'build resolves the customer id from the session and returns the avatar URL',
      () async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/profile/customer/c1/avatar') {
        return {'avatar_url': 'https://s3/cust-avatar.jpg'};
      }
      throw ApiException(message: 'unexpected GET $path', statusCode: 500);
    });
    final url =
        await container(api).read(customerAvatarControllerProvider.future);
    expect(url, 'https://s3/cust-avatar.jpg');
    expect(api.calls, isNot(contains('GET /auth/me')));
  });

  test('no avatar yet (404 on probe) → null, never throws', () async {
    final api = FakeApi(onGet: (path, _) async {
      throw const ApiException(message: 'not found', statusCode: 404);
    });
    final url =
        await container(api).read(customerAvatarControllerProvider.future);
    expect(url, isNull);
  });

  test('no session user → the load errors (own-only path needs the id)',
      () async {
    final api = FakeApi(onGet: (path, _) async => null);
    final c = container(api, session: seededNoUserSession());
    await expectLater(
      c.read(customerAvatarControllerProvider.future),
      throwsA(isA<ApiException>()),
    );
  });

  test(
      'upload posts multipart to the own-only customer path → state becomes the new URL',
      () async {
    final posted = <String>[];
    final api = FakeApi(
      onGet: (path, _) async {
        throw const ApiException(
            message: 'not found', statusCode: 404); // no avatar yet
      },
      onPost: (path, data) async {
        posted.add(path);
        return {'avatar_url': 'https://s3/new-cust-avatar.jpg'};
      },
    );
    final c = container(api);
    expect(await c.read(customerAvatarControllerProvider.future), isNull);

    final err = await c
        .read(customerAvatarControllerProvider.notifier)
        .upload(tempImage.path);

    expect(err, isNull);
    expect(posted, ['/profile/customer/c1/avatar']);
    expect(c.read(customerAvatarControllerProvider).value,
        'https://s3/new-cust-avatar.jpg');
  });

  test('upload failure → friendly message and the previous URL is kept',
      () async {
    final api = FakeApi(
      onGet: (path, _) async =>
          {'avatar_url': 'https://s3/old.jpg'}, // existing avatar
      onPost: (_, __) async {
        throw const ApiException(
            message:
                'MIME mismatch: declared image/jpeg but content is image/png',
            statusCode: 400);
      },
    );
    final c = container(api);
    expect(await c.read(customerAvatarControllerProvider.future),
        'https://s3/old.jpg');

    final err = await c
        .read(customerAvatarControllerProvider.notifier)
        .upload(tempImage.path);

    expect(
        err,
        isNot(
            contains('MIME mismatch'))); // friendly, not the raw server string
    expect(err, contains('JPEG'));
    // The previous avatar is preserved after a failed upload.
    expect(
        c.read(customerAvatarControllerProvider).value, 'https://s3/old.jpg');
  });
}
