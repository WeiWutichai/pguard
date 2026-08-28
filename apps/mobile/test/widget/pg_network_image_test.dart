import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/widgets/pg_network_image.dart';

void main() {
  group(
      'pgStableCacheKey (perf-review #6 — presigned re-mint hits the disk cache)',
      () {
    test('strips the volatile presigned query, keeps scheme+host+path', () {
      const a =
          'https://minio.example/pguard/avatars/g1.jpg?X-Amz-Signature=aaa&Expires=1';
      const b =
          'https://minio.example/pguard/avatars/g1.jpg?X-Amz-Signature=ZZZ&Expires=999';
      // Two different signed URLs for the SAME object → the SAME cache key (a re-mint is a hit).
      expect(PgNetworkImage.pgStableCacheKey(a),
          PgNetworkImage.pgStableCacheKey(b));
      expect(PgNetworkImage.pgStableCacheKey(a),
          'https://minio.example/pguard/avatars/g1.jpg');
    });

    test('different objects/users keep distinct keys', () {
      expect(
        PgNetworkImage.pgStableCacheKey('https://m.example/a/g1.jpg?s=1'),
        isNot(
            PgNetworkImage.pgStableCacheKey('https://m.example/a/g2.jpg?s=1')),
      );
    });

    test('a non-URL string falls back to itself', () {
      expect(PgNetworkImage.pgStableCacheKey('not a url'), 'not a url');
    });
  });

  testWidgets(
      'PgNetworkImage wires a CachedNetworkImage with the stable key + a downsized decode',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PgNetworkImage(
          url: 'https://m.example/pguard/x.jpg?sig=abc',
          width: 50,
          height: 50,
        ),
      ),
    ));

    final img =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(img.imageUrl, 'https://m.example/pguard/x.jpg?sig=abc');
    expect(img.cacheKey, 'https://m.example/pguard/x.jpg');
    // Downsized decode: memCacheWidth/Height are set (display px × devicePixelRatio), so a
    // multi-megapixel photo is not decoded at full resolution.
    expect(img.memCacheWidth, isNotNull);
    expect(img.memCacheHeight, isNotNull);
  });

  testWidgets(
      'downsize:false leaves the decode at full resolution (zoomable viewers)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PgNetworkImage(
          url: 'https://m.example/pguard/x.jpg?sig=abc',
          width: 50,
          height: 50,
          downsize: false,
        ),
      ),
    ));
    final img =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(img.memCacheWidth, isNull);
    expect(img.memCacheHeight, isNull);
  });

  test('pgCachedImageProvider carries the stable cache key', () {
    final provider = pgCachedImageProvider(
        'https://m.example/pguard/avatars/c1.jpg?X-Amz-Signature=xyz',
        diameterPx: 96);
    expect(provider, isA<CachedNetworkImageProvider>());
    expect((provider as CachedNetworkImageProvider).cacheKey,
        'https://m.example/pguard/avatars/c1.jpg');
  });
}
