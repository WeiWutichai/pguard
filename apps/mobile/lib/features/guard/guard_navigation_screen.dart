import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/controllers/guard_route_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/tracking_controller.dart';
import '../../core/location/routing_service.dart';
import '../../core/models/booking.dart';
import '../../core/models/geo.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/primary_button.dart';
import '../booking/widgets/pg_map.dart';

part 'guard_navigation_screen.g.dart';

/// The guard's own position for the navigation / inline-travel maps, as a LIVE `GeoPoint?` so the
/// map shows the guard moving + keeps the route fresh. `null` (no permission/fix yet) ⟹ the map
/// shows "กำลังหาตำแหน่ง".
///
/// ONE GPS SUBSCRIPTION during the job: when a presence lease is active (the guard is en_route /
/// arrived and [TrackingController] is already streaming device GPS to presence) this REUSES that
/// lease's latest fix ([TrackingState.lastSample]) instead of opening a SECOND geolocator stream —
/// the active-job screen runs in exactly that window, so the self-map rides the existing stream.
/// Only when NO lease is held (no streaming) does it fall back to a dedicated one-shot+stream self
/// feed, so the map still works outside the lease window.
@riverpod
Stream<GeoPoint?> guardSelfLocation(GuardSelfLocationRef ref) {
  // When a presence lease is active, REUSE its single OS subscription: watch the controller's last
  // fix directly (no second geolocator stream). The fixes are movement-gated (~15 m), so rebuilding
  // on each one is cheap; the map just re-emits the newest point. `null` until the first fix lands.
  final leaseActive =
      ref.watch(trackingControllerProvider.select((s) => s.streaming));
  if (leaseActive) {
    final sample =
        ref.watch(trackingControllerProvider.select((s) => s.lastSample));
    return Stream<GeoPoint?>.value(
        sample == null ? null : GeoPoint(sample.lat, sample.lng));
  }
  // No lease → a dedicated self feed (one-shot seed + the OS stream) for maps shown outside the job.
  return ref.read(locationServiceProvider).selfLocationStream();
}

/// Guard turn-to-site navigation (design `Mobile - Guard App.html` ④): a full-bleed REAL
/// OpenStreetMap map ([PgMap], flutter_map + OSM tiles) with the guard pin, the destination ring
/// and a REAL road route (a multi-point [PgPolyline] following the roads, via OSRM), an amber-dot
/// status pill, a glass back button, a รถยนต์/มอเตอร์ไซค์/เดิน travel-mode selector, and a sheet
/// showing the road distance + the selected-mode ETA with a single combined "arrived — start" CTA.
///
/// ROUTING: the road geometry + distance + driving time come from the public OSRM demo
/// ([RoutingService], no API key), keyed/cached by the snapped guard origin + destination
/// ([guardRouteProvider]) so it re-fetches only when the guard crosses a ~100 m cell — not on each
/// GPS tick — and the inline preview shares the same cached route. The mode selector switches ONLY
/// the ETA (the geometry is identical — the public demo serves the driving profile only).
///
/// FALLBACK: when OSRM is unreachable / returns no route, the screen DEGRADES to the honest
/// straight-line [PgPolyline] + the straight-line geo.dart distance·ETA, labelled `~` (a real
/// routed ETA carries no tilde) — never a blank map or a crash. The destination comes from the
/// booking's `lat`/`lng`; older bookings created without a map pin have none — the screen then
/// shows the address only (no map route / no distance). Reached from the active-job en-route stage.
class GuardNavigationScreen extends ConsumerWidget {
  const GuardNavigationScreen({super.key, required this.bookingId});

  final String bookingId;

  /// The "I've arrived" action: mark the job `arrived` (skipped when it is ALREADY `arrived` —
  /// advanced from another screen/frame), then return to the active-job screen. It deliberately
  /// does NOT start the work clock: starting + the checkpoint photo now happen on the active screen
  /// ("เช็คอินเริ่มงาน"), so the timer only runs once the guard has filed the start check-in on
  /// site — the active screen lands on `JobStage.start` after this pops. STATUS-GATED: pressed
  /// while the booking is no longer en_route/arrived (cancelled during a WS gap, still merely
  /// accepted) it explains instead of firing a guaranteed-409 PUT. The failure message prefers the
  /// controller's localized transition error over the generic fallback.
  Future<void> _confirmArrived(
      BuildContext context, WidgetRef ref, bool isThai) async {
    final ctrl = ref.read(activeJobControllerProvider(bookingId).notifier);
    final status = ref
        .read(activeJobControllerProvider(bookingId))
        .valueOrNull
        ?.booking
        .status;
    if (status != BookingStatus.enRoute && status != BookingStatus.arrived) {
      _snack(
          context,
          isThai
              ? 'สถานะงานเปลี่ยนไปแล้ว — กลับไปหน้างานเพื่อดูสถานะล่าสุด'
              : 'The job state changed — check the job screen for the latest');
      return;
    }
    if (status == BookingStatus.enRoute) {
      final arrived = await ctrl.arrived();
      if (!context.mounted) return;
      if (!arrived) {
        _snack(
            context,
            _ctrlError(ref) ??
                (isThai ? 'ทำรายการไม่สำเร็จ' : "Couldn't update the job"));
        return;
      }
    }
    if (context.mounted) context.pop();
  }

  /// The controller's localized transition error for this booking, if it recorded one.
  String? _ctrlError(WidgetRef ref) =>
      ref.read(activeJobControllerProvider(bookingId)).valueOrNull?.error;

  static void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(activeJobControllerProvider(bookingId));

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      body: async.when(
        loading: () => const _Plain(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _Plain(
          child: PgErrorState(
            title: isThai ? 'โหลดงานไม่สำเร็จ' : 'Could not load this job',
            message: e is ApiException ? e.message : null,
            onRetry: () =>
                ref.invalidate(activeJobControllerProvider(bookingId)),
          ),
        ),
        data: (state) {
          final b = state.booking;
          final dest = (b.lat != null && b.lng != null)
              ? GeoPoint(b.lat!, b.lng!)
              : null;
          final self = ref.watch(guardSelfLocationProvider).valueOrNull;
          return _NavBody(
            isThai: isThai,
            address: b.address,
            dest: dest,
            self: self,
            busy: state.busy,
            onArrive: () => _confirmArrived(context, ref, isThai),
          );
        },
      ),
    );
  }
}

class _NavBody extends ConsumerStatefulWidget {
  const _NavBody({
    required this.isThai,
    required this.address,
    required this.dest,
    required this.self,
    required this.busy,
    required this.onArrive,
  });

  final bool isThai;
  final String? address;
  final GeoPoint? dest;
  final GeoPoint? self;
  final bool busy;
  final VoidCallback onArrive;

  @override
  ConsumerState<_NavBody> createState() => _NavBodyState();
}

class _NavBodyState extends ConsumerState<_NavBody> {
  /// The guard-selected travel mode (default รถยนต์/car) — switches the ETA label only.
  TravelMode _mode = TravelMode.car;

  /// On-demand recenter trigger threaded into [PgMap.recenterToken]: bumped when the guard taps the
  /// sheet's ▲ to re-frame the map on the whole route after panning/zooming away. The map persists;
  /// only the camera re-fits (see PgMap.didUpdateWidget).
  int _recenterToken = 0;

  @override
  Widget build(BuildContext context) {
    final isThai = widget.isThai;
    final dest = widget.dest;
    final self = widget.self;
    final topInset = MediaQuery.of(context).padding.top;

    // The REAL road route — fetched once per (snapped) origin/dest and shared with the inline
    // preview via [guardRouteProvider]'s cache. `snapOrigin` throttles the family key to a ~100 m
    // grid so re-fetches happen only when the guard moves meaningfully, not on each GPS tick.
    final route = (self != null && dest != null)
        ? ref
            .watch(guardRouteProvider(
              start: snapOrigin(self),
              end: snapDest(dest),
            ))
            .valueOrNull
        : null;

    // Straight-line fallback estimate (geo.dart, labelled `~`) — used whenever there is no routed
    // result yet (loading) or routing failed/returned null (offline / OSRM down / no route).
    final fallback = (self != null && dest != null)
        ? TravelEstimate.between(self, dest)
        : null;

    final String primary;
    if (route != null) {
      // REAL route: road distance + the selected-mode ETA, NO tilde.
      primary =
          '${formatDistance(route.distanceMeters, thai: isThai)} · ${_mode.etaLabel(route, isThai)}';
    } else if (fallback != null) {
      // Fallback: straight-line distance·ETA, keeps the `~` to mark it approximate.
      primary =
          '${fallback.distanceLabel(isThai)} · ${fallback.etaLabel(isThai)}';
    } else {
      primary = isThai ? 'กำลังไปจุดนัด' : 'Heading to site';
    }

    return Stack(
      children: [
        // Full-bleed map: REAL road polyline when available, else the straight fallback segment.
        // Degrades to a plain backdrop when there are no coordinates to plot.
        Positioned.fill(
          child: _MapLayer(
            dest: dest,
            self: self,
            route: route,
            recenterToken: _recenterToken,
          ),
        ),
        // Honest no-fix state: the live self stream hasn't produced a position yet (permission /
        // cold GPS). Show "กำลังหาตำแหน่ง" over the destination map rather than a silent crosshair.
        if (self == null)
          Positioned(
            top: topInset + PgTokens.space7,
            left: 0,
            right: 0,
            child: Center(child: _LocatingChip(isThai: isThai)),
          ),
        // Status pill overlay.
        Positioned(
          top: topInset + PgTokens.space3,
          left: 0,
          right: 0,
          child: Center(
            child: _StatusPill(
              label: isThai ? 'กำลังไปจุดนัด' : 'Heading to site',
            ),
          ),
        ),
        // Glass back button.
        Positioned(
          top: topInset + PgTokens.space2,
          left: PgTokens.space3,
          child: _GlassBack(onTap: () => context.pop()),
        ),
        // Bottom sheet: the mode selector + distance·ETA + address + the combined arrive→start CTA.
        Align(
          alignment: Alignment.bottomCenter,
          child: _Sheet(
            isThai: isThai,
            primary: primary,
            address: widget.address ?? (isThai ? 'จุดนัดหมาย' : 'Destination'),
            // The selector only shows once there is something to estimate (a route or fallback);
            // it switches the ETA label between car / motorcycle / walk.
            mode: (route != null || fallback != null) ? _mode : null,
            onModeChanged: (m) => setState(() => _mode = m),
            // The sheet's ▲ re-frames the map on the whole route (guard + dest + road polyline) by
            // bumping the token PgMap watches — useful after the guard pans/zooms away.
            onRecenter: () => setState(() => _recenterToken++),
            busy: widget.busy,
            onArrive: widget.onArrive,
          ),
        ),
      ],
    );
  }
}

/// The real OSM map + route + guard/destination markers ([PgMap]). When [route] is present it draws
/// the REAL multi-point road polyline; otherwise it falls back to the honest straight 2-point line
/// between self and dest. Degrades to a plain (Bangkok-centred) tiled backdrop when there are no
/// coordinates to plot.
class _MapLayer extends StatelessWidget {
  const _MapLayer(
      {required this.dest,
      required this.self,
      this.route,
      this.recenterToken = 0});

  final GeoPoint? dest;
  final GeoPoint? self;
  final RouteResult? route;

  /// Threaded into [PgMap.recenterToken] — bumped by the sheet's ▲ to re-frame the whole route.
  final int recenterToken;

  @override
  Widget build(BuildContext context) {
    // Prefer the real road geometry; else the straight segment (fallback / pre-route loading).
    final List<GeoPoint>? linePoints = route != null
        ? route!.polyline
        : (self != null && dest != null ? [self!, dest!] : null);
    return PgMap(
      // LIVE FOLLOW: the camera centres on the guard's OWN live fix at nav zoom and follows it like
      // a nav app (it does NOT zoom out to the whole 36 km route). A manual pan pauses follow; the
      // sheet's ▲ (recenterToken) re-engages it. The map is NOT re-keyed, so it + the TileLayer
      // persist as the guard's fix updates (no tile re-fetch / flicker).
      follow: self,
      recenterToken: recenterToken,
      polyline: linePoints != null
          // The real route is a definite road path → solid; the fallback stays dashed (the
          // honest "this is a straight approximation" cue, matching the `~` label).
          ? PgPolyline(points: linePoints, dashed: route == null)
          : null,
      markers: [
        if (dest != null)
          PgMarker(
              point: dest!,
              width: 44,
              height: 44,
              child: const GuardNavDestMarker()),
        if (self != null)
          PgMarker(
              point: self!,
              width: 40,
              height: 40,
              child: const GuardNavGuardMarker()),
      ],
    );
  }
}

/// Design `.pin.guard`: a green badge with a shield. Public so the inline guard travel-map
/// preview reuses the exact same pin as the full navigation screen.
class GuardNavGuardMarker extends StatelessWidget {
  const GuardNavGuardMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PgTokens.colorGreen800,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: const Icon(Icons.shield, color: Colors.white, size: 18),
    );
  }
}

/// Design `.dest .ring`: a brand dot inside a soft ring. Public so the inline guard travel-map
/// preview reuses the exact same marker as the full navigation screen.
class GuardNavDestMarker extends StatelessWidget {
  const GuardNavDestMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: PgTokens.colorPrimary.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: PgTokens.colorPrimary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Design `.statuspill`: an amber-400 live dot + a short status label, over the map.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: PgTokens.space3, vertical: PgTokens.space1),
      decoration: BoxDecoration(
        // Design `.statuspill`: green-900 fill.
        color: PgTokens.colorGreen900,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: PgTokens.colorAmber400, shape: BoxShape.circle),
          ),
          const SizedBox(width: PgTokens.space1),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Honest "finding your location" chip shown over the map while the live self stream has not yet
/// produced a fix (replaces a silent blank crosshair). A small spinner + "กำลังหาตำแหน่ง".
class _LocatingChip extends StatelessWidget {
  const _LocatingChip({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: PgTokens.space3, vertical: PgTokens.space2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: PgTokens.colorPrimary),
          ),
          const SizedBox(width: PgTokens.space2),
          Text(
            isThai ? 'กำลังหาตำแหน่ง' : 'Finding your location',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorTextStrong),
          ),
        ],
      ),
    );
  }
}

/// Design `.iconbtn.glass`: a translucent white circle with the brand-green chevron.
class _GlassBack extends StatelessWidget {
  const _GlassBack({required this.onTap});
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
          padding: EdgeInsets.all(10),
          child: Icon(Icons.arrow_back_ios_new,
              size: 18, color: PgTokens.colorBrand),
        ),
      ),
    );
  }
}

/// Design ④ sheet: a 54px nav-icon tile + the distance·ETA and site address, the รถยนต์/มอเตอร์ไซค์/
/// เดิน travel-mode selector, then a single combined green CTA. Rounded-top with a grab handle; no
/// top border on the footer.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.isThai,
    required this.primary,
    required this.address,
    required this.mode,
    required this.onModeChanged,
    required this.onRecenter,
    required this.busy,
    required this.onArrive,
  });

  final bool isThai;
  final String primary;
  final String address;

  /// The selected travel mode, or null while there is nothing to estimate (no fix / no dest) —
  /// the selector is then hidden.
  final TravelMode? mode;
  final ValueChanged<TravelMode> onModeChanged;

  /// Tapping the ▲ tile re-frames the map on the whole route (the parent bumps the recenter token).
  final VoidCallback onRecenter;
  final bool busy;
  final VoidCallback onArrive;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
              color: Color(0x29082619), blurRadius: 36, offset: Offset(0, -10)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 5,
              margin: const EdgeInsets.only(top: 6, bottom: 14),
              decoration: BoxDecoration(
                color: PgTokens.colorBorderStrong,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(
                children: [
                  // The ▲ tile doubles as a RECENTER button: same green50 visual, now tappable with
                  // a ripple to re-frame the map on the whole route after the guard pans/zooms away.
                  Tooltip(
                    message: isThai ? 'จัดกึ่งกลางเส้นทาง' : 'Recenter route',
                    child: Semantics(
                      button: true,
                      label: isThai ? 'จัดกึ่งกลางเส้นทาง' : 'Recenter route',
                      child: Material(
                        color: PgTokens.colorGreen50,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onRecenter,
                          child: const SizedBox(
                            width: 54,
                            height: 54,
                            child: Icon(Icons.navigation,
                                color: PgTokens.colorPrimary, size: 26),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(primary,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: PgTokens.colorTextStrong)),
                        const SizedBox(height: 2),
                        Text(address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: PgTokens.colorTextMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (mode != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _ModeSelector(
                  isThai: isThai,
                  selected: mode!,
                  onChanged: onModeChanged,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: PgPrimaryButton(
                label: isThai ? 'ถึงจุดนัดแล้ว' : "I've arrived",
                busy: busy,
                onPressed: busy ? null : onArrive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The รถยนต์ / มอเตอร์ไซค์ / เดิน segmented selector — three equal chips that switch which ETA the
/// sheet shows (the route geometry is unchanged). The selected chip fills brand-green; the rest are
/// a calm sunken tile. Tapping a chip calls [onChanged].
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.isThai,
    required this.selected,
    required this.onChanged,
  });

  final bool isThai;
  final TravelMode selected;
  final ValueChanged<TravelMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      ),
      child: Row(
        children: [
          _ModeChip(
            icon: Icons.directions_car,
            label: isThai ? 'รถยนต์' : 'Car',
            active: selected == TravelMode.car,
            onTap: () => onChanged(TravelMode.car),
          ),
          _ModeChip(
            icon: Icons.two_wheeler,
            label: isThai ? 'มอเตอร์ไซค์' : 'Motorcycle',
            active: selected == TravelMode.motorcycle,
            onTap: () => onChanged(TravelMode.motorcycle),
          ),
          _ModeChip(
            icon: Icons.directions_walk,
            label: isThai ? 'เดิน' : 'Walk',
            active: selected == TravelMode.walk,
            onTap: () => onChanged(TravelMode.walk),
          ),
        ],
      ),
    );
  }
}

/// One pill in [_ModeSelector]. `active` → brand-green fill + white glyph; otherwise transparent
/// with muted text. Equal-width (wrapped in [Expanded] by the row).
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: active ? PgTokens.colorPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PgTokens.radiusFull),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16,
                    color: active ? Colors.white : PgTokens.colorTextMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : PgTokens.colorTextMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading/error chrome with a plain back affordance (the glass-on-map button needs the map).
class _Plain extends StatelessWidget {
  const _Plain({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: PgTokens.space2,
            left: PgTokens.space3,
            child: IconButton(
              icon:
                  const Icon(Icons.arrow_back, color: PgTokens.colorTextStrong),
              onPressed: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}
