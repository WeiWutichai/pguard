import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/storage/secure_store.dart';

/// perf-review #19: the auth interceptor reads the access token on EVERY request. [SecureStore]
/// now keeps a write-through in-memory cache so those reads don't decrypt the Keychain/Keystore
/// each time. These tests mock the flutter_secure_storage platform channel and COUNT reads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late Map<String, String> backing;
  late int channelReads;

  setUp(() {
    backing = {};
    channelReads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map).cast<String, dynamic>();
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          channelReads++;
          return backing[key];
        case 'write':
          backing[key!] = args['value'] as String;
          return null;
        case 'delete':
          backing.remove(key);
          return null;
        case 'deleteAll':
          backing.clear();
          return null;
        case 'containsKey':
          return backing.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(backing);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'repeated access-token reads are served from memory (no repeat channel reads)',
      () async {
    final store = SecureStore();
    await store.saveTokens(access: 'a1', refresh: 'r1');
    final before = channelReads;
    for (var i = 0; i < 5; i++) {
      expect(await store.readAccessToken(), 'a1');
    }
    expect(channelReads, before,
        reason: 'the write-through cache serves reads without a channel read');
  });

  test('the FIRST read hits the channel exactly once, then caches', () async {
    backing['pg_access_token'] = 'seeded';
    final store = SecureStore();
    final r0 = channelReads;
    expect(await store.readAccessToken(), 'seeded');
    expect(channelReads, r0 + 1, reason: 'first read populates the cache');
    expect(await store.readAccessToken(), 'seeded');
    expect(channelReads, r0 + 1, reason: 'subsequent reads are cached');
  });

  test('saveTokens refreshes the cache (a rotation is seen immediately)',
      () async {
    final store = SecureStore();
    await store.saveTokens(access: 'a1', refresh: 'r1');
    expect(await store.readAccessToken(), 'a1');
    await store.saveTokens(access: 'a2', refresh: 'r2');
    expect(await store.readAccessToken(), 'a2');
  });

  test('clearTokens / clearSession / wipe invalidate the cache to null',
      () async {
    final store = SecureStore();

    await store.saveTokens(access: 'a1', refresh: 'r1');
    await store.clearTokens();
    expect(await store.readAccessToken(), isNull);

    await store.saveTokens(access: 'a2', refresh: 'r2');
    await store.clearSession();
    expect(await store.readAccessToken(), isNull);

    await store.saveTokens(access: 'a3', refresh: 'r3');
    await store.wipe();
    expect(await store.readAccessToken(), isNull);
  });
}
