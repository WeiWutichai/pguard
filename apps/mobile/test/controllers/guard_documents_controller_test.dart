import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/guard_documents_controller.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

void main() {
  // A real temp JPEG on disk so the controller's MultipartFile.fromFile() can stat/read it.
  late File tempImage;
  setUp(() async {
    tempImage = File(
        '${Directory.systemTemp.path}/pg_doc_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
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
    // The controller is autoDispose — without a listener it would be disposed between reads (and a
    // re-read would restart its async build), so hold it alive for the duration of the test.
    c.listen(guardDocumentsControllerProvider, (_, __) {});
    return c;
  }

  /// A FakeApi that answers `/auth/me` with [guardId] and each documents probe from [stored]
  /// (a present key returns a presigned url; an absent one 404s, like the real GET).
  FakeApi probeApi({
    String guardId = 'g1',
    Map<String, String> stored = const {},
    Future<dynamic> Function(String path, Object? data)? onPost,
  }) {
    return FakeApi(
      onGet: (path, query) async {
        if (path == '/auth/me') return {'user_id': guardId};
        if (path == '/profile/guard/$guardId/documents') {
          final type = query?['document_type'] as String?;
          final url = stored[type];
          if (url == null) {
            throw const ApiException(message: 'not found', statusCode: 404);
          }
          return {'document_type': type, 'download_url': url};
        }
        throw ApiException(message: 'unexpected GET $path', statusCode: 500);
      },
      onPost: onPost,
    );
  }

  test('build probes every credential once → uploaded reflects server truth, no polling',
      () async {
    final api = probeApi(stored: {
      'id_card': 'https://s3/idcard.jpg',
      'security_license': 'https://s3/lic.jpg',
    });
    final c = container(api);
    final state = await c.read(guardDocumentsControllerProvider.future);

    expect(state.guardId, 'g1');
    expect(state.slots.length, GuardCredential.values.length);
    expect(state.slotFor(GuardCredential.idCard).uploaded, isTrue);
    expect(state.slotFor(GuardCredential.idCard).downloadUrl,
        'https://s3/idcard.jpg');
    expect(state.slotFor(GuardCredential.securityLicense).uploaded, isTrue);
    expect(state.slotFor(GuardCredential.trainingCert).uploaded, isFalse);
    expect(state.slotFor(GuardCredential.passbookPhoto).uploaded, isFalse);
    expect(state.uploadedCount, 2);

    // /auth/me once + one probe per credential — and NEVER repeated (no polling loop).
    expect(api.getCount, 1 + GuardCredential.values.length);
  });

  test('a probe error degrades that slot to not-uploaded (load never fails)', () async {
    // /auth/me ok, but every probe 500s — the whole load still resolves with empty slots.
    final api = FakeApi(onGet: (path, query) async {
      if (path == '/auth/me') return {'user_id': 'g1'};
      throw const ApiException(message: 'replica down', statusCode: 500);
    });
    final state =
        await container(api).read(guardDocumentsControllerProvider.future);
    expect(state.uploadedCount, 0);
    expect(state.slots.every((s) => !s.uploaded), isTrue);
  });

  test('missing user_id in /auth/me → the load errors (no guessing the path)', () async {
    final api = FakeApi(onGet: (path, _) async {
      if (path == '/auth/me') return <String, dynamic>{};
      return null;
    });
    final c = container(api);
    await expectLater(
        c.read(guardDocumentsControllerProvider.future), throwsA(isA<ApiException>()));
  });

  test('upload posts multipart to the own-only path → slot flips uploaded with the new url',
      () async {
    final posted = <String>[];
    final api = probeApi(onPost: (path, data) async {
      posted.add(path);
      return {'document_type': 'id_card', 'download_url': 'https://s3/new.jpg'};
    });
    final c = container(api);
    await c.read(guardDocumentsControllerProvider.future);

    final err = await c
        .read(guardDocumentsControllerProvider.notifier)
        .upload(GuardCredential.idCard, tempImage.path);

    expect(err, isNull);
    expect(posted, ['/profile/guard/g1/documents']);
    final slot = c
        .read(guardDocumentsControllerProvider)
        .value!
        .slotFor(GuardCredential.idCard);
    expect(slot.uploaded, isTrue);
    expect(slot.downloadUrl, 'https://s3/new.jpg');
    expect(slot.busy, isFalse);
    expect(slot.error, isNull);
  });

  test('upload failure surfaces the server message on the slot, stays not-uploaded', () async {
    final api = probeApi(onPost: (_, __) async {
      throw const ApiException(
          message: 'MIME mismatch: declared image/jpeg but content is image/png',
          statusCode: 400);
    });
    final c = container(api);
    await c.read(guardDocumentsControllerProvider.future);

    final err = await c
        .read(guardDocumentsControllerProvider.notifier)
        .upload(GuardCredential.idCard, tempImage.path);

    // The raw, technical English server string is mapped to a friendly bilingual message; the
    // 'MIME mismatch' detail never reaches the user. ('JPEG' appears in both the TH and EN copy.)
    expect(err, isNot(contains('MIME mismatch')));
    expect(err, contains('JPEG'));
    final slot = c
        .read(guardDocumentsControllerProvider)
        .value!
        .slotFor(GuardCredential.idCard);
    expect(slot.uploaded, isFalse);
    expect(slot.busy, isFalse);
    expect(slot.error, isNot(contains('MIME mismatch')));
    expect(slot.error, contains('JPEG'));
  });

  test('a second upload of the same credential while one is in flight is ignored (no double POST)',
      () async {
    var posts = 0;
    final gate = Completer<void>();
    final api = probeApi(onPost: (_, __) async {
      posts++;
      await gate.future;
      return {'document_type': 'id_card', 'download_url': 'https://s3/x.jpg'};
    });
    final c = container(api);
    await c.read(guardDocumentsControllerProvider.future);
    final notifier = c.read(guardDocumentsControllerProvider.notifier);

    final first = notifier.upload(GuardCredential.idCard, tempImage.path);
    // busy is set synchronously before the first await, so the second call sees the latch.
    final second = await notifier.upload(GuardCredential.idCard, tempImage.path);
    expect(second, isNull); // ignored, not an error

    gate.complete();
    expect(await first, isNull);
    expect(posts, 1);
  });

  test('GuardCredential wire keys match the profile.yaml document_type enum exactly (drift-lock)',
      () {
    // The contract's `document_type` enum (contracts/openapi/profile.yaml). If the backend adds
    // or renames a type, this test fails until the mobile enum is updated.
    const contractTypes = {
      'id_card',
      'security_license',
      'training_cert',
      'criminal_check',
      'driver_license',
      'passbook_photo',
    };
    expect(GuardCredential.values.map((c) => c.key).toSet(), contractTypes);
  });

  test('detectImageMime sniffs the magic bytes (mirrors the server detector)', () {
    expect(
        GuardDocumentsController.detectImageMime([0xFF, 0xD8, 0xFF, 0xE0]),
        'image/jpeg');
    expect(
        GuardDocumentsController.detectImageMime(
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        'image/png');
    expect(
        GuardDocumentsController.detectImageMime(
            [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]),
        'image/webp');
    // A PNG/WebP whose bytes were re-encoded to JPEG is detected as JPEG (the whole point).
    expect(
        GuardDocumentsController.detectImageMime([0xFF, 0xD8, 0xFF]), 'image/jpeg');
    // Non-image / too-short → null (caller defaults to JPEG; the server then rejects).
    expect(GuardDocumentsController.detectImageMime([0x00, 0x01, 0x02]), isNull);
    expect(GuardDocumentsController.detectImageMime(const []), isNull);
  });

  test('two concurrent uploads of different credentials both succeed (no slot clobber)',
      () async {
    final gates = {
      'id_card': Completer<void>(),
      'driver_license': Completer<void>(),
    };
    final api = probeApi(onPost: (path, data) async {
      final type = (data! as FormData)
          .fields
          .firstWhere((e) => e.key == 'document_type')
          .value;
      await gates[type]!.future;
      return {'document_type': type, 'download_url': 'https://s3/$type.jpg'};
    });
    final c = container(api);
    await c.read(guardDocumentsControllerProvider.future);
    final n = c.read(guardDocumentsControllerProvider.notifier);

    final f1 = n.upload(GuardCredential.idCard, tempImage.path);
    final f2 = n.upload(GuardCredential.driverLicense, tempImage.path);
    // Both in flight; release in REVERSE order to maximize the chance of a clobber if _patchSlot
    // captured a stale snapshot instead of re-reading.
    gates['driver_license']!.complete();
    gates['id_card']!.complete();
    expect(await Future.wait([f1, f2]), [null, null]);

    final st = c.read(guardDocumentsControllerProvider).value!;
    expect(st.slotFor(GuardCredential.idCard).uploaded, isTrue);
    expect(st.slotFor(GuardCredential.idCard).downloadUrl, 'https://s3/id_card.jpg');
    expect(st.slotFor(GuardCredential.driverLicense).uploaded, isTrue);
    expect(st.slotFor(GuardCredential.driverLicense).downloadUrl,
        'https://s3/driver_license.jpg');
    expect(st.uploadedCount, 2);
  });

  test('a completion AFTER the screen is disposed is a no-op (no throw, no late write)',
      () async {
    final gate = Completer<void>();
    final api = probeApi(onPost: (_, __) async {
      await gate.future;
      return {'document_type': 'id_card', 'download_url': 'https://s3/x.jpg'};
    });
    // A standalone container we dispose by hand (no addTearDown double-dispose).
    final c = ProviderContainer(
      overrides: [pguardApiProvider.overrideWithValue(api)],
    );
    c.listen(guardDocumentsControllerProvider, (_, __) {});
    await c.read(guardDocumentsControllerProvider.future);

    final f =
        c.read(guardDocumentsControllerProvider.notifier).upload(
              GuardCredential.idCard,
              tempImage.path,
            );
    c.dispose(); // screen popped mid-upload
    gate.complete();
    // The gated POST resolves after dispose; the controller's _disposed guard must swallow the
    // late state write rather than throw.
    await expectLater(f, completes);
  });
}
