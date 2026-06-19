import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/guard_avatar_controller.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  // A real temp JPEG so the upload's MultipartFile.fromFile() can stat/read it.
  late File tempImage;
  setUp(() async {
    tempImage = File(
        '${Directory.systemTemp.path}/pg_avatar_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tempImage.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  });
  tearDown(() async {
    if (await tempImage.exists()) await tempImage.delete();
  });

  ProviderContainer container(FakeApi api) {
    final c = ProviderContainer(
      overrides: [pguardApiProvider.overrideWithValue(api)],
    );
    addTearDown(c.dispose);
    // autoDispose — keep alive across awaits.
    c.listen(guardAvatarControllerProvider, (_, __) {});
    return c;
  }

  test('build resolves the guard id from /auth/me and returns the current avatar URL', () async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/auth/me') return {'user_id': 'g1'};
      if (path == '/profile/guard/g1/avatar') {
        return {'avatar_url': 'https://s3/avatar.jpg'};
      }
      throw ApiException(message: 'unexpected GET $path', statusCode: 500);
    });
    final url = await container(api).read(guardAvatarControllerProvider.future);
    expect(url, 'https://s3/avatar.jpg');
  });

  test('no avatar yet (404 on probe) → null, never throws', () async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/auth/me') return {'user_id': 'g1'};
      throw const ApiException(message: 'not found', statusCode: 404);
    });
    final url = await container(api).read(guardAvatarControllerProvider.future);
    expect(url, isNull);
  });

  test('missing user_id in /auth/me → the load errors (own-only path needs the id)', () async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/auth/me') return <String, dynamic>{};
      return null;
    });
    final c = container(api);
    await expectLater(
      c.read(guardAvatarControllerProvider.future),
      throwsA(isA<ApiException>()),
    );
  });

  test('upload posts multipart to the own-only path → state becomes the new URL', () async {
    final posted = <String>[];
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/auth/me') return {'user_id': 'g1'};
        throw const ApiException(message: 'not found', statusCode: 404); // no avatar yet
      },
      onPost: (path, data) async {
        posted.add(path);
        return {'avatar_url': 'https://s3/new-avatar.jpg'};
      },
    );
    final c = container(api);
    expect(await c.read(guardAvatarControllerProvider.future), isNull);

    final err = await c
        .read(guardAvatarControllerProvider.notifier)
        .upload(tempImage.path);

    expect(err, isNull);
    expect(posted, ['/profile/guard/g1/avatar']);
    expect(c.read(guardAvatarControllerProvider).value, 'https://s3/new-avatar.jpg');
  });

  test('upload failure → friendly message and the previous URL is kept', () async {
    final api = FakeApi(
      onGet: (path, _) async {
        if (path == '/auth/me') return {'user_id': 'g1'};
        return {'avatar_url': 'https://s3/old.jpg'}; // existing avatar
      },
      onPost: (_, __) async {
        throw const ApiException(
            message: 'MIME mismatch: declared image/jpeg but content is image/png',
            statusCode: 400);
      },
    );
    final c = container(api);
    expect(await c.read(guardAvatarControllerProvider.future), 'https://s3/old.jpg');

    final err = await c
        .read(guardAvatarControllerProvider.notifier)
        .upload(tempImage.path);

    expect(err, isNot(contains('MIME mismatch'))); // friendly, not the raw server string
    expect(err, contains('JPEG'));
    // The previous avatar is preserved after a failed upload.
    expect(c.read(guardAvatarControllerProvider).value, 'https://s3/old.jpg');
  });
}
