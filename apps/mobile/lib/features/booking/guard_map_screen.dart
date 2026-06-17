import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/guard_location_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/relative_time.dart';
import '../../core/controllers/session_controller.dart';
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
import 'widgets/map_canvas.dart';

/// The customer live-map: where is my guard right now? Watches ONLY
/// [GuardLocationController] — the snapshot re-pull is driven by booking-status WebSocket
/// events (and the refresh gesture), never a `Timer.periodic` (the v2 contract has no
/// customer-readable location stream; see the controller doc). The "map" is the same
/// no-SDK painted canvas the booking picker uses; ALL projection math lives in the pure
/// [MapViewport] (no business logic in this widget).
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

class _MapBody extends StatelessWidget {
  const _MapBody({
    required this.track,
    required this.isThai,
    required this.onRefresh,
  });

  final GuardTrack track;
  final bool isThai;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final guard = track.guard;
    // Where the guard is heading: the booking's pinned destination when present, else the
    // customer's device fix as a fallback (see GuardTrack.target).
    final target = track.target;
    final viewport = MapViewport.fit([
      if (guard != null) guard.point,
      if (target != null) target,
    ]);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    return Stack(
                      children: [
                        const Positioned.fill(
                          child:
                              CustomPaint(painter: MapBackdropPainter()),
                        ),
                        // The design's dashed brand route between the guard pin and the
                        // destination (pure paint — projection stays in MapViewport).
                        if (guard != null && target != null)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _RoutePathPainter(
                                from: viewport.fractionFor(guard.point),
                                to: viewport.fractionFor(target),
                              ),
                            ),
                          ),
                        if (target != null)
                          _placed(
                            viewport.fractionFor(target),
                            size,
                            width: 90,
                            height: 44,
                            child: _ReferenceMarker(
                              isThai: isThai,
                              isDestination: track.targetIsDestination,
                            ),
                          ),
                        if (guard != null)
                          _placed(
                            viewport.fractionFor(guard.point),
                            size,
                            width: 44,
                            height: 56,
                            child: _GuardMarker(heading: guard.heading),
                          ),
                        if (guard == null)
                          Center(child: _NoFixCard(track: track, isThai: isThai)),
                      ],
                    );
                  },
                ),
              ),
              Positioned(
                top: PgTokens.space3,
                left: PgTokens.space3,
                child: _StatusChip(status: track.status, isThai: isThai),
              ),
            ],
          ),
        ),
        _InfoPanel(track: track, isThai: isThai, onRefresh: onRefresh),
      ],
    );
  }

  /// Position [child] so its visual anchor sits on the viewport fraction.
  static Widget _placed(
    ({double x, double y}) frac,
    Size size, {
    required double width,
    required double height,
    required Widget child,
  }) {
    return Positioned(
      left: frac.x * size.width - width / 2,
      top: frac.y * size.height - height / 2,
      width: width,
      height: height,
      child: child,
    );
  }
}

/// The guard's pin: brand shield in a circle; the small arrow rotates to the reported heading.
class _GuardMarker extends StatelessWidget {
  const _GuardMarker({this.heading});

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
              BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
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
class _ReferenceMarker extends StatelessWidget {
  const _ReferenceMarker({required this.isThai, required this.isDestination});

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

/// The design's dashed route between the guard pin and the destination marker: brand
/// interactive at 70% opacity, 5px stroke, round caps, dash pattern "2 12". Inputs are
/// viewport FRACTIONS — all geo→canvas math stays in [MapViewport].
class _RoutePathPainter extends CustomPainter {
  const _RoutePathPainter({required this.from, required this.to});

  final ({double x, double y}) from;
  final ({double x, double y}) to;

  @override
  void paint(Canvas canvas, Size size) {
    final a = Offset(from.x * size.width, from.y * size.height);
    final b = Offset(to.x * size.width, to.y * size.height);
    final total = (b - a).distance;
    if (total <= 0) return;

    final paint = Paint()
      ..color = PgTokens.colorPrimary.withValues(alpha: 0.7)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final dir = (b - a) / total;
    // 2px dash + 12px gap stepped along the segment (round caps render the short
    // dashes as the design's dotted path).
    for (var d = 0.0; d < total; d += 14) {
      final end = math.min(d + 2, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePathPainter oldDelegate) =>
      oldDelegate.from != from || oldDelegate.to != to;
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
              style: const TextStyle(
                  fontSize: 13, color: PgTokens.colorTextMuted),
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
  });

  final GuardTrack track;
  final bool isThai;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guard = track.guard;
    final distance = track.distanceToTarget;
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
              style: const TextStyle(
                  fontSize: 12, color: PgTokens.colorTextMuted),
            ),
          if (distance != null)
            Text(
              track.targetIsDestination
                  ? (isThai
                      ? 'ห่างจากจุดหมายประมาณ ${formatDistance(distance, thai: true)}'
                      : 'About ${formatDistance(distance, thai: false)} from the destination')
                  : (isThai
                      ? 'ห่างจากคุณประมาณ ${formatDistance(distance, thai: true)}'
                      : 'About ${formatDistance(distance, thai: false)} from you'),
              style: const TextStyle(
                  fontSize: 12, color: PgTokens.colorTextMuted),
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
                enabled: booking.guardId != null &&
                    BookingLifecycle.isActive(booking.status),
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
