import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Disk-caching, DOWNSIZING network image — the app-wide replacement for raw `Image.network` /
/// `NetworkImage` on presigned media (avatars, chat thumbs, check-in photos, document previews).
///
/// Three wins over `Image.network` (perf-review 2026-08 finding #6):
///  1. **Disk cache** (via `cached_network_image`): the bytes survive a re-entry / navigation and a
///     low-memory ImageCache eviction, so re-opening a screen is a cache hit — not a re-download.
///  2. **Downsize on decode** (`memCacheWidth`/`memCacheHeight` ≈ display px × devicePixelRatio):
///     a multi-megapixel presigned photo is decoded to the size it is actually SHOWN at, instead of
///     full ARGB on the raster thread — the list-scroll jank cause.
///  3. **Stable cache key** ([pgStableCacheKey]): presigned URLs re-mint a fresh query string
///     (`X-Amz-Signature`, `Expires`, …) on every fetch, which would bust a URL-keyed cache on each
///     autoDispose rebuild. Keying on scheme+host+PATH (dropping the volatile query) makes a
///     re-minted URL for the SAME object a cache hit. Different objects/users keep distinct paths.
///
/// [placeholder] shows while the bytes load (default: nothing); [errorWidget] shows on a failed /
/// expired URL (default: nothing) — callers pass their existing monogram/icon fallbacks so the
/// degrade behaviour is unchanged from the `Image.network` `errorBuilder`/`loadingBuilder` they had.
class PgNetworkImage extends StatelessWidget {
  const PgNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.downsize = true,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Shown until the image decodes (mirrors the old `loadingBuilder`'s non-null-progress branch).
  final Widget? placeholder;

  /// Shown when the URL fails/expires (mirrors the old `errorBuilder`).
  final Widget? errorWidget;

  /// Optional rounded clip applied to the whole image (so callers don't wrap in a ClipRRect).
  final BorderRadius? borderRadius;

  /// When true (default) the decode is capped at the displayed [width]/[height] × devicePixelRatio.
  /// Set false for a full-screen zoomable viewer where the user pinch-zooms past the layout size.
  final bool downsize;

  /// The volatile-query-stripped cache key: scheme+host+path only. A presigned URL re-mint of the
  /// SAME object hits the disk cache instead of re-downloading. Public so tests can assert it.
  static String pgStableCacheKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return '${uri.scheme}://${uri.host}${uri.path}';
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    int? px(double? logical) =>
        (!downsize || logical == null || !logical.isFinite || logical <= 0)
            ? null
            : (logical * dpr).round();
    Widget image = CachedNetworkImage(
      imageUrl: url,
      cacheKey: pgStableCacheKey(url),
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: px(width),
      memCacheHeight: px(height),
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: placeholder == null ? null : (context, _) => placeholder!,
      errorWidget: (context, _, __) => errorWidget ?? const SizedBox.shrink(),
    );
    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}

/// An [ImageProvider] for `CircleAvatar.foregroundImage` — the disk-caching, downsizing, stable-key
/// equivalent of `NetworkImage(url)`. [diameterPx] downsizes the decode to the avatar's rendered
/// size (logical diameter × devicePixelRatio); pass it from `radius * 2 * MediaQuery.devicePixelRatio`.
ImageProvider pgCachedImageProvider(String url, {int? diameterPx}) {
  return CachedNetworkImageProvider(
    url,
    cacheKey: PgNetworkImage.pgStableCacheKey(url),
    maxWidth: diameterPx,
    maxHeight: diameterPx,
  );
}
