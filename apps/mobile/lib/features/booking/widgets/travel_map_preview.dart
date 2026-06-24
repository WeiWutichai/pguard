import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/models/geo.dart';
import 'pg_map.dart';

/// A short, inline LIVE travel-map card — the same OSM surface ([PgMap]) the full-screen
/// customer live-map and guard navigation use, sized down to fit the empty space below a status
/// card. It plots a [mover] pin (the guard, or the guard's own position) and a [target] pin (the
/// destination, or the customer), with a [PgPolyline] between them. When [routePoints] are supplied
/// (the guard nav preview passes the cached OSRM road geometry) it draws the REAL road route;
/// otherwise it falls back to the honest straight [mover]→[target] segment. Tapping anywhere (or the
/// fullscreen affordance) calls [onExpand], which both screens wire to push their full-screen map.
///
/// Re-uses the SAME live data the callers already watch (no new polling): each screen passes the
/// current points from its controller, and [PgMap] re-fits the camera imperatively as they move.
/// The [routePoints], when present, come from the shared `guardRouteProvider` cache (keyed by the
/// snapped origin/dest) so the preview never triggers its own per-rebuild OSRM fetch. The no-fix /
/// loading state degrades to a calm [placeholder] band — never a crash.
class TravelMapPreview extends StatelessWidget {
  const TravelMapPreview({
    super.key,
    required this.mover,
    required this.target,
    required this.moverMarker,
    required this.targetMarker,
    required this.onExpand,
    this.routePoints,
    this.height = 220,
    this.placeholder,
  });

  /// The thing in motion (the guard, or the guard's own device fix). `null` until a fix lands —
  /// the card then shows [placeholder].
  final GeoPoint? mover;

  /// Where [mover] is heading (booking destination, or the customer). `null` for a legacy
  /// address-only booking with no pinned coordinate — the map still centres on the [mover].
  final GeoPoint? target;

  /// The REAL road route (≥2 points) when available — drawn in place of the straight segment.
  /// Null → fall back to the straight [mover]→[target] line. Comes from the shared route cache.
  final List<GeoPoint>? routePoints;

  /// The pin drawn at [mover] (each screen passes its own styled marker).
  final Widget moverMarker;

  /// The pin drawn at [target].
  final Widget targetMarker;

  /// Tap / expand handler — pushes the caller's full-screen map.
  final VoidCallback onExpand;

  final double height;

  /// Shown when there is no [mover] fix to plot (loading / no signal). Defaults to a neutral band.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (mover == null)
              placeholder ?? const _PreviewPlaceholder()
            else
              // Static preview: pan/zoom is reserved for the full screen — a tap expands instead.
              PgMap(
                interactive: false,
                // Prefer the real road route (solid) when supplied; else the straight segment
                // (dashed — the honest "approximate" cue). Null when there is no target at all.
                polyline: (routePoints != null && routePoints!.length >= 2)
                    ? PgPolyline(points: routePoints!, dashed: false)
                    : (target != null
                        ? PgPolyline(points: [mover!, target!])
                        : null),
                markers: [
                  if (target != null)
                    PgMarker(
                      // A roomy box (labelled destination markers are a dot + a text pill) so the
                      // reused full-screen markers never overflow at preview scale.
                      point: target!,
                      width: 90,
                      height: 56,
                      child: targetMarker,
                    ),
                  PgMarker(
                    point: mover!,
                    width: 44,
                    height: 56,
                    child: moverMarker,
                  ),
                ],
              ),
            // Whole-card tap → expand (sits above the non-interactive map).
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onExpand),
              ),
            ),
            // Fullscreen affordance: a glass circle in the top-right corner.
            Positioned(
              top: PgTokens.space2,
              right: PgTokens.space2,
              child: _ExpandButton(onTap: onExpand),
            ),
          ],
        ),
      ),
    );
  }
}

/// The neutral band shown before any [mover] fix is available (loading / no signal).
class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PgTokens.colorSunken,
      alignment: Alignment.center,
      child: const Icon(Icons.location_searching,
          size: 22, color: PgTokens.colorTextMuted),
    );
  }
}

/// Design `.iconbtn.glass`: a translucent white circle with a brand-green fullscreen glyph.
class _ExpandButton extends StatelessWidget {
  const _ExpandButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child:
              Icon(Icons.fullscreen, size: 18, color: PgTokens.colorBrand),
        ),
      ),
    );
  }
}
