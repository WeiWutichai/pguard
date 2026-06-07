import '../config/app_config.dart';

/// Rewrites the host of a presigned media URL so a device can actually reach it.
///
/// MinIO/S3 hands back presigned URLs whose authority is the storage host as the SERVER sees it
/// (e.g. `http://minio:9000/...` inside docker, or `http://localhost:9000/...`). A phone/emulator
/// can't resolve those, so we swap the scheme+authority for a reachable public media host while
/// preserving the path AND the signature query (which must not be altered). PURE + unit-testable.
class MediaHost {
  const MediaHost._();

  /// Swap [url]'s scheme+authority for [publicHost] (e.g. `https://media.pguard.app`), keeping
  /// the path + query (the presigned signature) intact. Returns [url] unchanged when [publicHost]
  /// is empty, or when [url] is not an absolute http(s) URL (relative refs / data URIs pass through).
  ///
  /// [publicHost] must be a scheme+authority only (`https://host[:port]`); any path on it is
  /// ignored. The source path/query is copied byte-for-byte (no re-encoding of the signature).
  static String rewrite(String url, {required String publicHost}) {
    if (publicHost.isEmpty) return url;
    final src = Uri.tryParse(url);
    if (src == null || !src.hasScheme || !(src.isScheme('http') || src.isScheme('https'))) {
      return url;
    }
    final host = Uri.tryParse(publicHost);
    if (host == null || !host.hasAuthority) return url;

    // Swap ONLY the scheme+authority; keep the path/query/fragment byte-for-byte so the presigned
    // signature query is never re-encoded (Uri.replace would re-encode / keep the old port).
    final schemeSep = url.indexOf('://');
    final afterScheme = schemeSep + 3;
    var tailStart = url.length;
    for (final sep in const ['/', '?', '#']) {
      final i = url.indexOf(sep, afterScheme);
      if (i != -1 && i < tailStart) tailStart = i;
    }
    final authority =
        host.hasPort ? '${host.host}:${host.port}' : host.host;
    return '${host.scheme}://$authority${url.substring(tailStart)}';
  }

  /// App-bound convenience: rewrite using the configured [AppConfig.mediaHost] (no-op when unset).
  static String forApp(String url) => rewrite(url, publicHost: AppConfig.mediaHost);
}
