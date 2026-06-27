import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/guard_location_controller.dart';
import '../../core/controllers/guard_route_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/relative_time.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/location/routing_service.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/models/geo.dart';
import '../../core/models/guard_public_profile.dart';
import '../../core/models/rating.dart';
import '../../core/models/tracking.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/star_rating.dart';
import '../call/widgets/call_entry_button.dart';
import '../chat/widgets/chat_entry_button.dart';
import 'widgets/pg_map.dart';

/// The customer live-map: where is my guard right now? Watches ONLY
/// [GuardLocationController] — the snapshot re-pull is driven by booking-status WebSocket
/// events (and the refresh gesture), never a `Timer.periodic` (the v2 contract has no
/// customer-readable location stream; see the controller doc). The map is a REAL
/// OpenStreetMap surface ([PgMap], flutter_map + OSM tiles), the same widget the booking
/// picker uses; the guard + destination markers ride on top.
///
/// REAL ROUTING (matches the guard nav): the line between the guard and the destination is the REAL
/// road route from the shared [guardRouteProvider] (OSRM via [RoutingService]), keyed by the SNAPPED
/// guard origin (the guard's LIVE position) + the booking destination — so it is fetched once per
/// ~100 m cell and CACHED (the inline preview shares the same route; no re-fetch on each guard GPS
/// update). The guard pin animates along that real road line as it moves. FALLBACK: when the route is
/// null (OSRM down / no guard fix yet) the map DEGRADES to the honest straight [guard]→[target]
/// segment, and the distance readout stays straight-line "≈" via geo.dart; when a route IS available
/// the distance shows the real ROAD distance (no "≈"). Never blank/crash.
class GuardMapScreen extends ConsumerWidget {
  const GuardMapScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(guardLocationControllerProvider(bookingId));
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: isThai ? 'ตำแหน่งเจ้าหน้าที่' : 'Guard location',
        subtitle: isThai ? 'อัปเดตตามสถานะงานแบบสด' : 'Live with job status',
        showBack: true,
        live: true,
        background: PgTokens.colorGreen800,
      ),
      body: SafeArea(
        child: async.when(
          // Keep the last map on screen while an event-driven re-pull is in flight.
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorBody(
            isThai: isThai,
            message: e is ApiException
                ? e.message
                : (isThai
                    ? 'ไม่สามารถโหลดตำแหน่งได้ในขณะนี้'
                    : 'Could not load the location right now'),
            onRetry: () => ref
                .read(guardLocationControllerProvider(bookingId).notifier)
                .refresh(),
          ),
          data: (track) => _MapBody(
            track: track,
            isThai: isThai,
            onRefresh: () => ref
                .read(guardLocationControllerProvider(bookingId).notifier)
                .refresh(),
          ),
        ),
      ),
    );
  }
}

class _MapBody extends ConsumerStatefulWidget {
  const _MapBody({
    required this.track,
    required this.isThai,
    required this.onRefresh,
  });

  final GuardTrack track;
  final bool isThai;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_MapBody> createState() => _MapBodyState();
}

class _MapBodyState extends ConsumerState<_MapBody> {
  /// On-demand recenter trigger threaded into [PgMap.recenterToken]: bumped when the customer taps
  /// the recenter FAB to re-frame the map on the guard + destination after panning/zooming away.
  /// The map persists; only the camera re-fits (see PgMap.didUpdateWidget).
  int _recenterToken = 0;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final isThai = widget.isThai;
    final guard = track.guard;
    // Where the guard is heading: the booking's pinned destination when present, else the
    // customer's device fix as a fallback (see GuardTrack.target).
    final target = track.target;

    // The REAL road route, shared with the inline preview via [guardRouteProvider]'s cache — origin =
    // the guard's LIVE position, dest = the booking target. `snapOrigin` quantises the origin to a
    // ~100 m grid so a fresh OSRM fetch fires only when the guard crosses a cell, not on each GPS
    // tick. Null (loading / OSRM down / no fix) → the straight-line fallback below.
    final route = (guard != null && target != null)
        ? ref
            .watch(guardRouteProvider(
              start: snapOrigin(guard.point),
              end: snapDest(target),
            ))
            .valueOrNull
        : null;

    // The line to draw: the REAL multi-point road geometry when routed, else the honest straight
    // 2-point segment (fallback / pre-route loading).
    final List<GeoPoint>? linePoints = route != null
        ? route.polyline
        : (guard != null && target != null ? [guard.point, target] : null);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              // Real OSM map: PgMap re-fits the camera IMPERATIVELY (didUpdateWidget) as the guard
              // moves / the snapshot changes — NOT re-keyed, so the single map + TileLayer persists
              // across WebSocket updates (no tile re-fetch / flicker). Route + markers ride on top.
              Positioned.fill(
                child: PgMap(
                  interactive: true,
                  // LIVE FOLLOW: the camera centres on the GUARD's live position at nav zoom and
                  // follows it as new fixes arrive (nav-app feel) — it does NOT zoom out to the whole
                  // route. A manual pan pauses follow; the recenter FAB re-engages it. The map is NOT
                  // re-keyed, so it + the TileLayer persist across WebSocket updates (no flicker).
                  follow: guard?.point,
                  recenterToken: _recenterToken,
                  // The real route is a definite road path → solid; the straight fallback stays
                  // dashed (the honest "this is a straight approximation" cue, matching the "≈"
                  // distance label below).
                  polyline: linePoints != null
                      ? PgPolyline(points: linePoints, dashed: route == null)
                      : null,
                  markers: [
                    if (target != null)
                      PgMarker(
                        point: target,
                        width: 90,
                        height: 44,
                        alignment: Alignment.center,
                        child: GuardMapReferenceMarker(
                          isThai: isThai,
                          isDestination: track.targetIsDestination,
                        ),
                      ),
                    if (guard != null)
                      PgMarker(
                        point: guard.point,
                        width: 44,
                        height: 56,
                        alignment: Alignment.center,
                        child: GuardMapGuardMarker(heading: guard.heading),
                      ),
                  ],
                ),
              ),
              if (guard == null)
                Center(child: _NoFixCard(track: track, isThai: isThai)),
              Positioned(
                top: PgTokens.space3,
                left: PgTokens.space3,
                child: _StatusChip(status: track.status, isThai: isThai),
              ),
              // Recenter affordance: re-frames the map on the guard + destination after the customer
              // pans/zooms away. Shown only when there is something to frame (a guard fix or target);
              // bumps the token PgMap watches (no re-key / flicker), bottom-right above the sheet.
              if (guard != null || target != null)
                Positioned(
                  right: PgTokens.space3,
                  bottom: PgTokens.space3,
                  child: _RecenterFab(
                    isThai: isThai,
                    onTap: () => setState(() => _recenterToken++),
                  ),
                ),
            ],
          ),
        ),
        _InfoPanel(
          track: track,
          isThai: isThai,
          onRefresh: widget.onRefresh,
          route: route,
        ),
      ],
    );
  }
}

/// A small circular recenter button floated over the customer tracking map (bottom-right, above the
/// sheet). Brand-styled (white circle, brand-green crosshair glyph) with a ripple + Semantics/Tooltip
/// so the customer can re-focus the guard-tracking map after panning/zooming away — taps [onTap],
/// which bumps the token PgMap re-fits on.
class _RecenterFab extends StatelessWidget {
  const _RecenterFab({required this.isThai, required this.onTap});

  final bool isThai;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = isThai ? 'จัดกึ่งกลางแผนที่' : 'Recenter map';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: PgTokens.colorSurface,
          shape: const CircleBorder(),
          elevation: 3,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.my_location,
                  size: 22, color: PgTokens.colorPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// The guard's pin: brand shield in a circle; the small arrow rotates to the reported heading.
/// Public so the inline customer live-map preview reuses the exact same pin as the full screen.
class GuardMapGuardMarker extends StatelessWidget {
  const GuardMapGuardMarker({super.key, this.heading});

  final double? heading;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: PgTokens.colorGreen800,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: const Icon(Icons.shield, color: Colors.white, size: 19),
        ),
        if (heading != null)
          Transform.rotate(
            // Heading 0° = north (up); Icons.navigation points up, so rotate by the bearing.
            angle: heading! * 3.1415926535 / 180,
            child: const Icon(Icons.navigation,
                size: 14, color: PgTokens.colorGreen800),
          ),
      ],
    );
  }
}

/// The destination marker — a labelled dot. Labelled "ปลายทาง / Destination" when it is the
/// booking's pinned drop-off (`GuardTrack.destination`), or "คุณ / You" when it falls back to the
/// customer's device fix (a legacy/address-only booking with no pinned coordinate).
/// Public so the inline customer live-map preview reuses the exact same marker as the full screen.
class GuardMapReferenceMarker extends StatelessWidget {
  const GuardMapReferenceMarker(
      {super.key, required this.isThai, required this.isDestination});

  final bool isThai;
  final bool isDestination;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: PgTokens.colorPrimary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(PgTokens.radiusSm),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
          ),
          child: Text(
            isDestination
                ? (isThai ? 'ปลายทาง' : 'Destination')
                : (isThai ? 'คุณ' : 'You'),
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorText),
          ),
        ),
      ],
    );
  }
}

/// The tracking pill over the map: amber live dot + customer-directed copy while the guard
/// is en route ("กำลังเดินทางมาหาคุณ" — a screen-local override; the shared lifecycle labels
/// stay guard-neutral), lifecycle labels otherwise. Dot = the design's amber-400 (exact
/// token since the full-ramp regen).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.isThai});

  final BookingStatus status;
  final bool isThai;

  String get _label {
    if (status == BookingStatus.enRoute) {
      return isThai ? 'กำลังเดินทางมาหาคุณ' : 'On the way to you';
    }
    return isThai
        ? BookingLifecycle.labelTh(status)
        : BookingLifecycle.labelEn(status);
  }

  @override
  Widget build(BuildContext context) {
    final negative = BookingLifecycle.isNegativeTerminal(status);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: PgTokens.space3, vertical: PgTokens.space1),
      decoration: BoxDecoration(
        color: negative ? PgTokens.colorDanger : PgTokens.colorGreen800,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!negative) ...[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: PgTokens.colorAmber400,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: PgTokens.space1),
          ],
          Text(
            _label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Centre overlay when there is no guard fix to draw (unassigned / no signal / job ended).
class _NoFixCard extends StatelessWidget {
  const _NoFixCard({required this.track, required this.isThai});

  final GuardTrack track;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (track.guardId == null) {
      text = isThai ? 'กำลังค้นหาเจ้าหน้าที่…' : 'Finding a guard…';
    } else if (BookingLifecycle.isTerminal(track.status)) {
      text = isThai
          ? 'งานสิ้นสุดแล้ว — ไม่มีตำแหน่งสด'
          : 'Job ended — live location unavailable';
    } else {
      text = isThai
          ? 'ยังไม่มีสัญญาณตำแหน่งจากเจ้าหน้าที่'
          : 'No location signal from the guard yet';
    }
    return Container(
      margin: const EdgeInsets.all(PgTokens.space6),
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_searching,
              size: 18, color: PgTokens.colorTextMuted),
          const SizedBox(width: PgTokens.space2),
          Flexible(
            child: Text(
              text,
              style:
                  const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom card: freshness (LIVE / last-seen), accuracy band, distance-from-you, the design's
/// chat/call action row, address + the one-shot refresh gesture.
class _InfoPanel extends ConsumerWidget {
  const _InfoPanel({
    required this.track,
    required this.isThai,
    required this.onRefresh,
    this.route,
  });

  final GuardTrack track;
  final bool isThai;
  final Future<void> Function() onRefresh;

  /// The REAL road route to the target when one is available — its road distance replaces the
  /// straight-line haversine in the distance readout (and drops the "≈" approximate cue). Null →
  /// the straight-line geo.dart distance, labelled "≈".
  final RouteResult? route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guard = track.guard;
    // Prefer the REAL road distance (along the route) when routed — that is an exact road figure, so
    // it drops the "≈". Fall back to the straight-line haversine ([GuardTrack.distanceToTarget]),
    // which stays approximate.
    final routed = route != null;
    final distance = route?.distanceMeters ?? track.distanceToTarget;
    final booking = track.booking;
    final myUserId = ref.watch(sessionProvider).user?.userId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: const BoxDecoration(
        color: PgTokens.colorSurface,
        border: Border(top: BorderSide(color: PgTokens.colorBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The design's guard-identity block (Screen 9) — shown once a guard is assigned, even
          // before any GPS fix. Honest data only: real name or a generic role label, real rating
          // or "no reviews yet", no photo, no ETA.
          if (track.guardId != null) ...[
            _GuardProfileBlock(
              profile: track.profile,
              ratings: track.ratings,
              isThai: isThai,
            ),
            const SizedBox(height: PgTokens.space3),
            const Divider(height: 1, color: PgTokens.colorBorder),
            const SizedBox(height: PgTokens.space3),
          ],
          Row(
            children: [
              Expanded(
                child: guard == null
                    ? Text(
                        isThai ? 'ไม่มีตำแหน่งสด' : 'No live position',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      )
                    : _Freshness(guard: guard, isThai: isThai),
              ),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                color: PgTokens.colorPrimary,
                tooltip: isThai ? 'รีเฟรชตำแหน่ง' : 'Refresh location',
              ),
            ],
          ),
          if (guard != null || distance != null)
            const SizedBox(height: PgTokens.space1),
          if (guard != null)
            Text(
              isThai
                  ? 'ความแม่นยำ: ${GpsAccuracyBand.of(guard.accuracy).labelTh}'
                  : 'Accuracy: ${GpsAccuracyBand.of(guard.accuracy).labelEn}',
              style:
                  const TextStyle(fontSize: 12, color: PgTokens.colorTextMuted),
            ),
          if (distance != null)
            Text(
              // A routed (real road) distance is exact → no "ประมาณ"/"About" hedge; the straight-line
              // fallback keeps the approximate wording. The device-fix target ("from you") is only
              // ever straight-line.
              track.targetIsDestination
                  ? (routed
                      ? (isThai
                          ? 'ระยะตามถนน ${formatDistance(distance, thai: true)} ถึงจุดหมาย'
                          : '${formatDistance(distance, thai: false)} by road to the destination')
                      : (isThai
                          ? 'ห่างจากจุดหมายประมาณ ${formatDistance(distance, thai: true)}'
                          : 'About ${formatDistance(distance, thai: false)} from the destination'))
                  : (isThai
                      ? 'ห่างจากคุณประมาณ ${formatDistance(distance, thai: true)}'
                      : 'About ${formatDistance(distance, thai: false)} from you'),
              style:
                  const TextStyle(fontSize: 12, color: PgTokens.colorTextMuted),
            ),
          // The design's tracking-sheet action row: chat + call (same enable rules as the
          // live-status screen — chat once a guard is assigned, call while the job is active).
          const SizedBox(height: PgTokens.space3),
          Row(
            children: [
              ChatEntryButton(
                requestId: booking.id,
                requestStatus: booking.status.wire,
                acting: ChatRole.customer,
                myUserId: myUserId,
                counterpartUserId: booking.guardId,
              ),
              const SizedBox(width: PgTokens.space2),
              Text(
                isThai ? 'แชต' : 'Chat',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorPrimary),
              ),
              const SizedBox(width: PgTokens.space4),
              CallEntryButton(
                bookingId: booking.id,
                // Callable window matches the calling service (accepted/en_route/arrived + guard
                // assigned); pendingCompletion is active but NOT callable → would 409.
                enabled: booking.guardId != null &&
                    BookingLifecycle.isCallable(booking.status),
              ),
              const SizedBox(width: PgTokens.space2),
              Text(
                isThai ? 'โทร' : 'Call',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorPrimary),
              ),
            ],
          ),
          if (track.booking.address != null) ...[
            const SizedBox(height: PgTokens.space2),
            Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 15, color: PgTokens.colorTextFaint),
                const SizedBox(width: PgTokens.space1),
                Expanded(
                  child: Text(
                    track.booking.address!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: PgTokens.colorTextFaint),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The assigned guard's identity card on the tracking sheet (design Screen 9 profile block):
/// avatar (initials from the name, or a brand shield when no name is known — never a fabricated
/// photo), the guard's name (a generic role label when the profile read is unavailable — never a
/// fabricated name), an experience line, and an HONEST rating row. No ETA minutes (no routing
/// service — distance only, shown elsewhere on the sheet).
class _GuardProfileBlock extends StatelessWidget {
  const _GuardProfileBlock({
    required this.profile,
    required this.ratings,
    required this.isThai,
  });

  final GuardPublicProfile? profile;
  final GuardRatings? ratings;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final name = profile?.fullName ??
        (isThai ? 'เจ้าหน้าที่รักษาความปลอดภัย' : 'Security guard');
    final initials = profile?.initials;
    final years = profile?.yearsOfExperience;
    return Row(
      children: [
        // Avatar: initials when we know the name, else a brand shield (no fabricated photo).
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PgTokens.colorGreen100,
            borderRadius: BorderRadius.circular(PgTokens.radiusMd),
          ),
          child: initials != null
              ? Text(
                  initials,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: PgTokens.colorGreen800),
                )
              // No name → a person placeholder (NOT the brand shield, which is the map pin).
              : const Icon(Icons.person,
                  size: 24, color: PgTokens.colorGreen800),
        ),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: PgTokens.space1),
                  // Assigned ⇒ an approved/registered guard — a STATIC, justified badge (NOT a
                  // per-guard verified flag the contract doesn't expose).
                  const Icon(Icons.verified,
                      size: 15, color: PgTokens.colorInfo),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _subtitle(years),
                style: const TextStyle(
                    fontSize: 12, color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: 3),
              _RatingRow(ratings: ratings, isThai: isThai),
            ],
          ),
        ),
      ],
    );
  }

  /// "Registered guard" always (assignment implies approval), plus the real years of experience
  /// when known — never invented.
  String _subtitle(int? years) {
    final registered = isThai ? 'รปภ. ขึ้นทะเบียน' : 'Registered guard';
    if (years == null || years <= 0) return registered;
    final exp = isThai ? 'ประสบการณ์ $years ปี' : '$years yr experience';
    return '$registered · $exp';
  }
}

/// HONEST rating row: filled stars + numeric average + count when there ARE visible reviews;
/// otherwise a plain "no reviews yet" — never a fabricated 0.0 (see [GuardRatings.hasRatings]).
class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.ratings, required this.isThai});

  final GuardRatings? ratings;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final r = ratings;
    if (r == null || !r.hasRatings) {
      return Text(
        isThai ? 'ยังไม่มีรีวิว' : 'No reviews yet',
        style: const TextStyle(fontSize: 12, color: PgTokens.colorTextFaint),
      );
    }
    final avg = r.averageValue!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StarRatingDisplay(value: avg.round(), size: 13),
        const SizedBox(width: PgTokens.space1),
        Text(
          '${avg.toStringAsFixed(1)} (${r.count})',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: PgTokens.colorText),
        ),
      ],
    );
  }
}

/// "LIVE" when the server says the fix is fresh, else a relative "last seen" line.
class _Freshness extends StatelessWidget {
  const _Freshness({required this.guard, required this.isThai});

  final GuardLocation guard;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    if (guard.isLive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: PgTokens.colorPrimary, shape: BoxShape.circle),
          ),
          const SizedBox(width: PgTokens.space1),
          Text(
            isThai ? 'ตำแหน่งสด' : 'Live position',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    final now = DateTime.now();
    final String label;
    if (isThai) {
      label = 'อัปเดตล่าสุด ${RelativeTime.th(guard.recordedAt, now: now)}';
    } else {
      // RelativeTime.en returns a phrase ('just now') under a minute — don't append 'ago'.
      final ago = RelativeTime.en(guard.recordedAt, now: now);
      label = ago == 'just now' ? 'Last seen just now' : 'Last seen $ago ago';
    }
    return Text(
      label,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.isThai,
    required this.message,
    required this.onRetry,
  });

  final bool isThai;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PgTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: PgTokens.colorTextMuted),
            const SizedBox(height: PgTokens.space3),
            Text(
              isThai ? 'ยังโหลดตำแหน่งไม่ได้' : 'Location unavailable',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: PgTokens.space2),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: PgTokens.colorTextMuted, fontSize: 13),
            ),
            const SizedBox(height: PgTokens.space4),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(isThai ? 'ลองอีกครั้ง' : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
