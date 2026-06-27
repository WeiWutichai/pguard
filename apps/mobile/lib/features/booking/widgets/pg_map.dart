import 'dart:async';

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

/// The navigation zoom the camera holds while FOLLOWING a live point ([PgMap.follow]) — close
/// enough to read the road around the moving pin (a nav-app feel), not the whole-route overview.
const double _kFollowZoom = 16;

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
/// ## Two camera modes
///
/// 1. **Live follow** ([follow] non-null) — the customer tracking map (follow the GUARD) and the
///    guard navigation map (follow the guard's OWN fix) pass the live point here. The camera
///    CENTRES on it at [followZoom] (~16, a nav-app feel) and KEEPS following as it updates — it
///    does NOT zoom out to the whole route. When the user manually pans/zooms, follow PAUSES (the
///    map doesn't fight the user); it re-engages on the next [recenterToken] bump.
/// 2. **Fit-all** ([follow] null) — the booking picker / inline previews: when ≥2 coordinates are
///    supplied the camera frames them all; a lone point centres at the current zoom; empty centres
///    on [center]/[initialZoom] (Bangkok default). [onTap] lifts a tap into a [GeoPoint] (the
///    picker's tap-to-place). The [recenterToken] bump re-fits all points.
///
/// ## Why a single persistent map (no re-key)
///
/// The live screens push fresh fixes every WebSocket / GPS tick. PgMap moves the camera
/// IMPERATIVELY (it does not re-key/remount the [FlutterMap]) so tiles never re-fetch and the
/// camera state is preserved across updates.
///
/// The widget fills its parent — wrap it in an [AspectRatio] / [SizedBox] / [Positioned.fill].
class PgMap extends StatefulWidget {
  const PgMap({
    super.key,
    this.center,
    this.initialZoom = 14,
    this.markers = const [],
    this.polyline,
    this.follow,
    this.followZoom = _kFollowZoom,
    this.onTap,
    this.borderRadius,
    this.interactive = true,
    this.minZoom = 3,
    this.maxZoom = 18,
    this.recenterToken = 0,
  });

  /// Where to centre when there is nothing to fit (0 or 1 marker, no [follow]). Defaults to Bangkok.
  final GeoPoint? center;
  final double initialZoom;
  final List<PgMarker> markers;
  final PgPolyline? polyline;

  /// LIVE-FOLLOW target. When non-null the camera CENTRES on this point at [followZoom] and follows
  /// it as it changes (nav-app behaviour) — it does NOT fit the whole route. A manual pan/zoom
  /// pauses the follow until the next [recenterToken] bump (so the map never fights the user). Null
  /// (the picker / previews) ⟹ the fit-all behaviour described on [PgMap].
  final GeoPoint? follow;

  /// The zoom held while following [follow]. Default [_kFollowZoom] (~16, a navigation zoom).
  final double followZoom;

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

  /// An on-demand RECENTER trigger. After the user pans/zooms away there is no coordinate change to
  /// re-frame the camera, so a parent (the guard-nav sheet's ▲, the customer map's recenter FAB)
  /// bumps this integer. A bump re-CENTRES on [follow] at [followZoom] AND re-engages auto-follow
  /// (when [follow] is null it re-fits all points instead). An unchanged token never moves the
  /// camera. Default 0 = never asked.
  final int recenterToken;

  @override
  State<PgMap> createState() => _PgMapState();
}

class _PgMapState extends State<PgMap> {
  final MapController _controller = MapController();

  /// True once flutter_map has actually laid the map out with a real (non-zero) pixel size — set by
  /// [_onMapReady] AND by the first [MapEventNonRotatedSizeChange] on [MapController.mapEventStream].
  /// Calling `fitCamera`/`move` before this is a SILENT no-op on a real device (the camera's
  /// `nonRotatedSize` is still zero, so the fit/move math is dropped) — which is exactly why the
  /// on-device camera looked dead while widget tests (synchronous layout) passed. We hold the latest
  /// requested camera move in [_pending] and flush it the instant the map becomes ready.
  bool _ready = false;
  _CameraRequest? _pending;
  StreamSubscription<MapEvent>? _eventSub;

  /// While true, auto-follow is suspended because the USER panned/zoomed (we don't yank the camera
  /// back from under them). A [recenterToken] bump (or a fresh non-null [follow] target appearing)
  /// clears it. Detected from `onPositionChanged(camera, hasGesture)`.
  bool _followPaused = false;

  /// Guards [_onPositionChanged]: our own programmatic moves come back through the same callback
  /// (with `hasGesture == false`), but a flung/settling gesture can also report `hasGesture == false`
  /// mid-animation — so we only ever set the pause flag from a `hasGesture == true` report, and use
  /// this to ignore the position event our own [_applyCamera] move triggers.
  bool _selfMoving = false;

  List<GeoPoint> _pointsOf(PgMap w) => [
        for (final m in w.markers) m.point,
        ...?w.polyline?.points,
      ];

  List<GeoPoint> get _allPoints => _pointsOf(widget);

  /// The [CameraFit] for a ≥2-coordinate set — used by the fit-all mode (no [follow]) both on open
  /// and on a recenter. Kept identical between init and the imperative path so the framing matches.
  static CameraFit _coordinatesFit(List<GeoPoint> points) =>
      CameraFit.coordinates(
        coordinates: points.map(toLatLng).toList(),
        padding: const EdgeInsets.all(48),
        maxZoom: 16,
      );

  @override
  void initState() {
    super.initState();
    // The first real size arrives as a MapEventNonRotatedSizeChange — a more reliable "the camera
    // can actually be moved now" signal than onMapReady alone (which can fire a frame before the
    // render box is sized). Either one flips [_ready] and flushes a pending request.
    _eventSub = _controller.mapEventStream.listen(_onMapEvent);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PgMap old) {
    super.didUpdateWidget(old);

    // 1) LIVE FOLLOW: the follow target moved → re-centre on it (unless the user paused follow by
    //    panning). Snapping into follow from a null target (the first fix lands) always engages.
    final follow = widget.follow;
    if (follow != null) {
      final justEngaged = old.follow == null;
      final moved = old.follow == null ||
          old.follow!.lat != follow.lat ||
          old.follow!.lng != follow.lng;
      if (justEngaged) {
        _followPaused = false; // a fresh target re-engages follow
      }
      if (moved && !_followPaused) {
        _request(_CameraRequest.center(toLatLng(follow), widget.followZoom));
      }
    }

    // 2) RECENTER: the parent bumped the token (the ▲ / FAB) → re-engage follow and re-centre on the
    //    live point at nav zoom; or, with no follow target, re-fit all points. A bump with unchanged
    //    points still recenters; an unchanged token never does.
    if (widget.recenterToken != old.recenterToken) {
      _followPaused = false;
      _request(_recenterRequest());
    }

    // 3) FIT-ALL (no follow): the plotted coordinate set changed → re-frame. The follow mode owns
    //    its own re-centre above, so only do this when NOT following.
    if (follow == null) {
      final points = _allPoints;
      if (!_pointsEqual(points, _pointsOf(old))) {
        _request(_fitRequest(points));
      }
    }
  }

  /// The camera request a RECENTER (token bump) should apply: centre on the live [follow] point at
  /// nav zoom when following, else fit all the plotted points (the picker / route-overview mode).
  _CameraRequest _recenterRequest() {
    final follow = widget.follow;
    if (follow != null) {
      return _CameraRequest.center(toLatLng(follow), widget.followZoom);
    }
    return _fitRequest(_allPoints);
  }

  /// The fit-all camera request for [points]: fit when ≥2, recentre keeping zoom on a lone point,
  /// no-op when empty.
  _CameraRequest _fitRequest(List<GeoPoint> points) {
    if (points.length >= 2) return _CameraRequest.fit(_coordinatesFit(points));
    if (points.length == 1) {
      return _CameraRequest.center(toLatLng(points.first), null);
    }
    return const _CameraRequest.none();
  }

  /// Apply [req] now if the map is ready, otherwise stash it as the [_pending] request to flush the
  /// instant the map becomes ready. The newest request always wins (an in-flight follow tick
  /// supersedes an older one).
  void _request(_CameraRequest req) {
    if (req.isNone) return;
    if (_ready) {
      _applyCamera(req);
    } else {
      _pending = req;
    }
  }

  void _applyCamera(_CameraRequest req) {
    _selfMoving = true;
    switch (req.kind) {
      case _CameraKind.fit:
        _controller.fitCamera(req.fit!);
      case _CameraKind.center:
        // Keep the current zoom when none is requested (a lone fit-all point); use the explicit
        // nav zoom when following.
        _controller.move(req.center!, req.zoom ?? _controller.camera.zoom);
      case _CameraKind.none:
        break;
    }
    _selfMoving = false;
  }

  void _onMapEvent(MapEvent event) {
    // The first real (non-zero) size lands as a MapEventNonRotatedSizeChange — the camera can now be
    // moved for real. Flip ready + flush whatever the parent last asked for while we were sizing.
    if (!_ready && event is MapEventNonRotatedSizeChange) {
      _markReady();
    }
  }

  void _onMapReady() {
    // Belt-and-braces alongside the size-change event: whichever fires first makes the map ready.
    _markReady();
  }

  void _markReady() {
    if (_ready) return;
    _ready = true;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      _applyCamera(pending);
    } else {
      // No queued request → apply the on-open framing now that the size is real (the picker's
      // fit-all, or — when following — centre on the live point at nav zoom).
      _applyCamera(_initialRequest());
    }
  }

  /// The on-open camera: centre on the [follow] point at nav zoom when following, else fit all the
  /// plotted points (or centre a lone one). Applied once the map is ready (its size is real).
  _CameraRequest _initialRequest() {
    final follow = widget.follow;
    if (follow != null) {
      return _CameraRequest.center(toLatLng(follow), widget.followZoom);
    }
    return _fitRequest(_allPoints);
  }

  /// flutter_map reports EVERY camera move through `onPositionChanged` with a `hasGesture` flag.
  /// A user pan/zoom (`hasGesture == true`) pauses auto-follow so the map stops chasing the live
  /// point until the next recenter; our own programmatic moves ([_selfMoving]) never pause it.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture && !_selfMoving) {
      _followPaused = true;
    }
  }

  /// Two coordinate sets are equal iff same length and same lat/lng in order — drives the
  /// "did anything move?" check in the fit-all branch of [didUpdateWidget].
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
    // The INITIAL camera (pre-ready): when following, sit on the live point at nav zoom; else fit
    // all coordinates (≥2) / centre the single point / fall back to center/Bangkok. The real
    // framing is re-applied imperatively in [_markReady] once the map has a real size.
    final follow = widget.follow;
    final CameraFit? initialFit =
        (follow == null && points.length >= 2) ? _coordinatesFit(points) : null;
    final GeoPoint initialCenter;
    final double initialZoom;
    if (follow != null) {
      initialCenter = follow;
      initialZoom = widget.followZoom;
    } else if (points.length == 1) {
      initialCenter = points.first;
      initialZoom = widget.initialZoom;
    } else {
      initialCenter = widget.center ?? GeoPoint.bangkok;
      initialZoom = widget.initialZoom;
    }

    final map = FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: toLatLng(initialCenter),
        initialZoom: initialZoom,
        initialCameraFit: initialFit,
        onMapReady: _onMapReady,
        onPositionChanged: _onPositionChanged,
        minZoom: widget.minZoom,
        maxZoom: widget.maxZoom,
        onTap: widget.onTap == null
            ? null
            : (_, latlng) => widget.onTap!(fromLatLng(latlng)),
        interactionOptions: InteractionOptions(
          flags:
              widget.interactive ? InteractiveFlag.all : InteractiveFlag.none,
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

/// What [_PgMapState] wants the camera to do — captured so a request made before the map is ready
/// (its size still zero) can be flushed the instant it becomes ready, instead of being silently
/// dropped by flutter_map.
enum _CameraKind { fit, center, none }

class _CameraRequest {
  const _CameraRequest._(this.kind, {this.fit, this.center, this.zoom});

  const _CameraRequest.none() : this._(_CameraKind.none);

  /// Frame a [CameraFit] (the fit-all mode's ≥2-point framing).
  const _CameraRequest.fit(CameraFit fit) : this._(_CameraKind.fit, fit: fit);

  /// Centre on [center]; [zoom] null ⇒ keep the current zoom (a lone fit-all point), non-null ⇒
  /// the explicit nav zoom (live follow / recenter).
  const _CameraRequest.center(LatLng center, double? zoom)
      : this._(_CameraKind.center, center: center, zoom: zoom);

  final _CameraKind kind;
  final CameraFit? fit;
  final LatLng? center;
  final double? zoom;

  bool get isNone => kind == _CameraKind.none;
}
