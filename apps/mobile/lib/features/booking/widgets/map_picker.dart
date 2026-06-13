import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/location/location_service.dart';
import '../../../core/models/geo.dart';
import '../../../core/providers.dart';
import 'map_canvas.dart';

/// An inline location picker: a draggable pin over a styled map canvas plus a "use current
/// location" action. Tapping or dragging moves the pin, which maps to a real lat/lng (a local
/// equirectangular projection around Bangkok); the coordinate is reverse-geocoded to a place
/// name via the injectable [LocationService]. No native map SDK, no network in tests, and no
/// `Timer.periodic` — geocoding is a one-shot future on each move. The resolved [GeoPlace] is
/// reported via [onChanged] (and stored as the booking address).
class MapPicker extends ConsumerStatefulWidget {
  const MapPicker({super.key, this.initial, required this.onChanged});

  final GeoPlace? initial;
  final ValueChanged<GeoPlace> onChanged;

  /// Degrees of latitude/longitude spanned across the visible canvas (the picker's zoom).
  static const double span = 0.04;

  @override
  ConsumerState<MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends ConsumerState<MapPicker> {
  late GeoPoint _point = widget.initial?.point ?? GeoPoint.bangkok;
  late String _placeName = widget.initial?.placeName ?? '';
  bool _resolving = false;

  GeoPoint get _center => GeoPoint.bangkok;

  /// Pin centre as a fraction [0,1] of the canvas, derived from the coordinate.
  Offset _fractionFor(GeoPoint p) {
    final nx = ((p.lng - _center.lng) / MapPicker.span + 0.5).clamp(0.04, 0.96);
    final ny = (0.5 - (p.lat - _center.lat) / MapPicker.span).clamp(0.04, 0.96);
    return Offset(nx.toDouble(), ny.toDouble());
  }

  GeoPoint _pointFor(Offset localFraction) {
    final nx = localFraction.dx.clamp(0.0, 1.0);
    final ny = localFraction.dy.clamp(0.0, 1.0);
    final lng = _center.lng + (nx - 0.5) * MapPicker.span;
    final lat = _center.lat + (0.5 - ny) * MapPicker.span;
    return GeoPoint(lat, lng);
  }

  void _moveTo(GeoPoint point) {
    setState(() => _point = point);
    _resolve();
  }

  Future<void> _resolve() async {
    // Capture the coordinate this geocode is for; if the pin moves again while we await, a
    // newer _resolve() is in flight — discard this (stale) result so the name/coordinate pair
    // never gets crossed.
    final pointAtCall = _point;
    setState(() => _resolving = true);
    final name =
        await ref.read(locationServiceProvider).reverseGeocode(pointAtCall);
    if (!mounted || pointAtCall != _point) return;
    setState(() {
      _placeName = name;
      _resolving = false;
    });
    widget.onChanged(GeoPlace(point: pointAtCall, placeName: name));
  }

  Future<void> _useCurrentLocation() async {
    final fix = await ref.read(locationServiceProvider).currentLocation();
    _moveTo(fix ?? GeoPoint.bangkok);
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(PgTokens.radiusXl),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final frac = _fractionFor(_point);
                final size = constraints.biggest;
                return GestureDetector(
                  onTapDown: (d) => _moveTo(_pointFor(Offset(
                      d.localPosition.dx / size.width,
                      d.localPosition.dy / size.height))),
                  onPanUpdate: (d) => setState(() => _point = _pointFor(Offset(
                      d.localPosition.dx / size.width,
                      d.localPosition.dy / size.height))),
                  onPanEnd: (_) => _resolve(),
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(painter: MapBackdropPainter()),
                      ),
                      Positioned(
                        left: frac.dx * size.width - 18,
                        top: frac.dy * size.height - 36,
                        child: const _Pin(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: PgTokens.space2),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _placeName.isEmpty
                        ? (isThai
                            ? 'แตะหรือลากหมุดเพื่อเลือกตำแหน่ง'
                            : 'Tap or drag the pin to set a location')
                        : _placeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorText),
                  ),
                  Text(
                    _point.label,
                    style: const TextStyle(
                        fontSize: 11, color: PgTokens.colorTextFaint),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _resolving ? null : _useCurrentLocation,
              icon: const Icon(Icons.my_location, size: 16),
              label: Text(isThai ? 'ตำแหน่งปัจจุบัน' : 'Current location'),
              style:
                  TextButton.styleFrom(foregroundColor: PgTokens.colorPrimary),
            ),
          ],
        ),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: PgTokens.colorPrimary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.shield, color: Colors.white, size: 18),
        ),
        Container(width: 2, height: 10, color: PgTokens.colorPrimary),
      ],
    );
  }
}
