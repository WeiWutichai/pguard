import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/models/geo.dart';

/// The OpenStreetMap raster tile endpoint. Free, no API key. flutter_map fetches
/// `{z}/{x}/{y}` PNG tiles from this template; the [TileLayer] adds the required
/// `User-Agent` from [_userAgentPackageName] (OSM's tile-usage policy mandates a UA).
const String _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Sent as the tile request User-Agent — OSM blocks anonymous bulk clients, so this
/// identifies the app (matches the FCM sender id / bundle id `app.pguard.mobile`).
const String _userAgentPackageName = 'app.pguard.mobile';

/// GeoPoint → flutter_map/latlong2 [LatLng]. Kept tiny + local so the rest of the app
/// keeps speaking [GeoPoint] (pure, unit-tested in geo.dart) and only PgMap touches LatLng.
LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

/// latlong2 [LatLng] → [GeoPoint] (the inverse of [toLatLng]) — used to lift a map tap back
/// into the app's coordinate type.
GeoPoint fromLatLng(LatLng p) => GeoPoint(p.latitude, p.longitude);

/// A marker to render on [PgMap]: a coordinate plus the widget drawn at it (the brand pin,
/// the guard shield, the destination ring…). [width]/[height] size the marker's tap/paint box;
/// [alignment] anchors the box on the coordinate (default: the box centre sits on the point —
/// pass [Alignment.bottomCenter] for a pin whose TIP should sit on the coordinate).
class PgMarker {
  const PgMarker({
    required this.point,
    required this.child,
    this.width = 44,
    this.height = 44,
    this.alignment = Alignment.center,
  });

  final GeoPoint point;
  final Widget child;
  final double width;
  final double height;
  final Alignment alignment;
}

/// A straight line drawn between [points] (we have no directions API — the route is the honest
/// straight segment, see geo.dart). [dashed] renders the design's dotted brand path; solid
/// otherwise.
class PgPolyline {
  const PgPolyline({
    required this.points,
    this.color = PgTokens.colorPrimary,
    this.strokeWidth = 4,
    this.dashed = true,
  });

  final List<GeoPoint> points;
  final Color color;
  final double strokeWidth;
  final bool dashed;
}

/// A REAL OpenStreetMap map (flutter_map) with the brand's rounded card framing — the single
/// reusable map surface for the booking picker, the customer live-map and the guard navigation
/// screen. Replaces the hand-painted `MapBackdropPainter`: real OSM tiles underneath, the
/// existing markers/route/pins layered on top (callers keep owning ALL their marker/route logic
/// and the distance/ETA readouts — those are straight-line via geo.dart, unchanged).
///
/// Layout: fits [markers] (+ [polyline]) into view when more than one coordinate is supplied,
/// else centres on [center]/[initialZoom]. [onTap] lifts a tap on the map into a [GeoPoint]
/// (the picker's tap-to-place). The widget fills its parent — wrap it in an [AspectRatio] /
/// [SizedBox] / [Positioned.fill] like the painted backdrop it replaces.
class PgMap extends StatefulWidget {
  const PgMap({
    super.key,
    this.center,
    this.initialZoom = 14,
    this.markers = const [],
    this.polyline,
    this.onTap,
    this.borderRadius,
    this.interactive = true,
    this.minZoom = 3,
    this.maxZoom = 18,
    this.recenterToken = 0,
  });

  /// Where to centre when there is nothing to fit (0 or 1 marker). Defaults to Bangkok.
  final GeoPoint? center;
  final double initialZoom;
  final List<PgMarker> markers;
  final PgPolyline? polyline;

  /// Tap-to-place: receives the tapped coordinate (the booking picker uses this). Null = the map
  /// is display-only (pan/zoom but no tap-to-place).
  final ValueChanged<GeoPoint>? onTap;

  /// Card corner radius. Null = square (full-bleed screens like guard navigation); the picker
  /// passes [PgTokens.radiusXl].
  final double? borderRadius;

  /// When false the map is a static, non-pannable preview (job-detail card).
  final bool interactive;
  final double minZoom;
  final double maxZoom;

  /// An on-demand re-fit trigger. After the user pans/zooms away there is no coordinate change to
  /// re-frame the camera, so a parent (the guard-nav sheet's ▲, the customer map's recenter FAB)
  /// bumps this integer to re-fit the camera to the CURRENT points — see [didUpdateWidget]. A bump
  /// with unchanged points still re-fits; an unchanged token never does. Default 0 = never asked.
  final int recenterToken;

  @override
  State<PgMap> createState() => _PgMapState();
}

class _PgMapState extends State<PgMap> {
  final MapController _controller = MapController();

  List<GeoPoint> _pointsOf(PgMap w) => [
        for (final m in w.markers) m.point,
        ...?w.polyline?.points,
      ];

  List<GeoPoint> get _allPoints => _pointsOf(widget);

  /// The init-only [CameraFit] for a ≥2-coordinate set (the same fit [didUpdateWidget] applies
  /// imperatively). Kept identical between init and update so the camera frames the markers the
  /// same way whether the map first mounts or the coordinates change underneath it.
  static CameraFit _coordinatesFit(List<GeoPoint> points) => CameraFit.coordinates(
        coordinates: points.map(toLatLng).toList(),
        padding: const EdgeInsets.all(48),
        maxZoom: 16,
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PgMap old) {
    super.didUpdateWidget(old);
    // Re-fit IMPERATIVELY (no remount/TileLayer re-fetch/flicker) when EITHER the plotted coordinate
    // set changed (the live customer map + guard navigation push fresh guard fixes every WebSocket
    // update — this replaces re-keying the whole widget on moving coordinates) OR the parent bumped
    // [recenterToken] to ask for an on-demand re-frame after the user panned/zoomed away (coordinates
    // unchanged). A no-op rebuild (same points, same token) must NOT re-fit. The single FlutterMap +
    // TileLayer persists across both; only the camera moves.
    final points = _allPoints;
    final pointsChanged = !_pointsEqual(points, _pointsOf(old));
    final recenterRequested = widget.recenterToken != old.recenterToken;
    if (!pointsChanged && !recenterRequested) return;
    _fitTo(points);
  }

  /// Frame the camera on [points] imperatively: fit all when there are ≥2, recentre (keeping the
  /// current zoom) on a lone point, no-op when empty. Shared by the coordinate-change and the
  /// [recenterToken] on-demand re-fit so both frame the map identically.
  void _fitTo(List<GeoPoint> points) {
    if (points.length >= 2) {
      _controller.fitCamera(_coordinatesFit(points));
    } else if (points.length == 1) {
      // One coordinate (the picker's tap-to-place pin, or a lone fix) → recentre, keep the zoom.
      _controller.move(toLatLng(points.first), _controller.camera.zoom);
    }
  }

  /// Two coordinate sets are equal iff same length and same lat/lng in order — drives the
  /// "did anything move?" check in [didUpdateWidget] (a no-op rebuild must not re-fit the camera).
  static bool _pointsEqual(List<GeoPoint> a, List<GeoPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].lat != b[i].lat || a[i].lng != b[i].lng) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final points = _allPoints;
    // Fit all coordinates when there are at least two; otherwise centre on the single point /
    // the provided center / Bangkok at the requested zoom.
    final fit = points.length >= 2 ? _coordinatesFit(points) : null;
    final center = points.length == 1
        ? points.first
        : (widget.center ?? GeoPoint.bangkok);

    final map = FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: toLatLng(center),
        initialZoom: widget.initialZoom,
        initialCameraFit: fit,
        minZoom: widget.minZoom,
        maxZoom: widget.maxZoom,
        onTap: widget.onTap == null
            ? null
            : (_, latlng) => widget.onTap!(fromLatLng(latlng)),
        interactionOptions: InteractionOptions(
          flags: widget.interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: _osmTileUrl,
          userAgentPackageName: _userAgentPackageName,
          maxZoom: 19,
        ),
        if (widget.polyline != null && widget.polyline!.points.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.polyline!.points.map(toLatLng).toList(),
                color: widget.polyline!.color.withValues(alpha: 0.85),
                strokeWidth: widget.polyline!.strokeWidth,
                pattern: widget.polyline!.dashed
                    ? const StrokePattern.dotted(spacingFactor: 2.2)
                    : const StrokePattern.solid(),
              ),
            ],
          ),
        if (widget.markers.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final m in widget.markers)
                Marker(
                  point: toLatLng(m.point),
                  width: m.width,
                  height: m.height,
                  alignment: m.alignment,
                  child: m.child,
                ),
            ],
          ),
      ],
    );

    if (widget.borderRadius == null) return map;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius!),
      child: map,
    );
  }
}
