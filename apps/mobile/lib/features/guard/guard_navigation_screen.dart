import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/geo.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/primary_button.dart';
import '../booking/widgets/pg_map.dart';

part 'guard_navigation_screen.g.dart';

/// The guard's own position as a LIVE stream (the same device GPS the guard streams to presence,
/// not a single stale one-shot) so the navigation map shows the guard moving + keeps the route
/// fresh. Seeds with a one-shot fix, then tracks every subsequent fix (no `Timer.periodic` — it is
/// the OS position stream). `null` (no permission/fix yet) ⟹ the map shows "กำลังหาตำแหน่ง".
@riverpod
Stream<GeoPoint?> guardSelfLocation(GuardSelfLocationRef ref) =>
    ref.read(locationServiceProvider).selfLocationStream();

/// Guard turn-to-site navigation (design `Mobile - Guard App.html` ④): a full-bleed REAL
/// OpenStreetMap map ([PgMap], flutter_map + OSM tiles) with the guard pin, the destination ring
/// and a straight dashed route, an amber-dot status pill, a glass back button, and a sheet showing
/// the approximate distance·ETA + the site address with a single combined "arrived — start" CTA.
///
/// HONEST LIMITS: there is no directions API, so the route is a straight line and the distance·ETA
/// are straight-line approximations (labelled `~`). The destination comes from the booking's
/// `lat`/`lng`; older bookings created without a map pin have none — the screen then shows the
/// address only (no map route / no distance). Reached from the active-job en-route stage.
class GuardNavigationScreen extends ConsumerWidget {
  const GuardNavigationScreen({super.key, required this.bookingId});

  final String bookingId;

  /// The combined "I've arrived — start" action: mark arrived, then start the work clock, then
  /// return to the active-job (now working) screen. Surfaces a message and stays put on failure.
  Future<void> _arriveAndStart(
      BuildContext context, WidgetRef ref, bool isThai) async {
    final ctrl = ref.read(activeJobControllerProvider(bookingId).notifier);
    final arrived = await ctrl.arrived();
    if (!context.mounted) return;
    if (!arrived) {
      _snack(context, isThai ? 'ทำรายการไม่สำเร็จ' : "Couldn't update the job");
      return;
    }
    final started = await ctrl.start();
    if (!context.mounted) return;
    if (started) {
      context.pop();
    } else {
      _snack(context, isThai ? 'เริ่มงานไม่สำเร็จ' : "Couldn't start the job");
    }
  }

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
            onArrive: () => _arriveAndStart(context, ref, isThai),
          );
        },
      ),
    );
  }
}

class _NavBody extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final estimate = (self != null && dest != null)
        ? TravelEstimate.between(self!, dest!)
        : null;

    return Stack(
      children: [
        // Full-bleed painted map with the route + pins (degrades to a plain backdrop when there
        // are no coordinates to plot).
        Positioned.fill(child: _MapLayer(dest: dest, self: self)),
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
        // Bottom sheet: distance·ETA + address + the combined arrive→start CTA.
        Align(
          alignment: Alignment.bottomCenter,
          child: _Sheet(
            isThai: isThai,
            primary: estimate != null
                ? '${estimate.distanceLabel(isThai)} · ${estimate.etaLabel(isThai)}'
                : (isThai ? 'กำลังไปจุดนัด' : 'Heading to site'),
            address: address ?? (isThai ? 'จุดนัดหมาย' : 'Destination'),
            busy: busy,
            onArrive: onArrive,
          ),
        ),
      ],
    );
  }
}

/// The real OSM map + straight dashed route + guard/destination markers ([PgMap]). Degrades to a
/// plain (Bangkok-centred) tiled backdrop when there are no coordinates to plot.
class _MapLayer extends StatelessWidget {
  const _MapLayer({required this.dest, required this.self});

  final GeoPoint? dest;
  final GeoPoint? self;

  @override
  Widget build(BuildContext context) {
    return PgMap(
      // PgMap re-fits the camera imperatively (didUpdateWidget) when either coordinate changes —
      // not re-keyed, so the map + TileLayer persist as the guard's own fix updates (no flicker).
      polyline: (self != null && dest != null)
          ? PgPolyline(points: [self!, dest!])
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

/// Design ④ sheet: a 54px nav-icon tile + the approximate distance·ETA and site address, then a
/// single combined green CTA. Rounded-top with a grab handle; no top border on the footer.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.isThai,
    required this.primary,
    required this.address,
    required this.busy,
    required this.onArrive,
  });

  final bool isThai;
  final String primary;
  final String address;
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
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: PgTokens.colorGreen50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.navigation,
                        color: PgTokens.colorPrimary, size: 26),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: PgPrimaryButton(
                label: isThai ? 'ถึงจุดนัดแล้ว — เริ่มงาน' : "I've arrived — start",
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
              icon: const Icon(Icons.arrow_back,
                  color: PgTokens.colorTextStrong),
              onPressed: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}
