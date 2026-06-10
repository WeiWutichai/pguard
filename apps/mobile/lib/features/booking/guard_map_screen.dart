import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/guard_location_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/relative_time.dart';
import '../../core/models/booking.dart';
import '../../core/models/geo.dart';
import '../../core/models/tracking.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pguard_header.dart';
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
    final viewport = MapViewport.fit([
      if (guard != null) guard.point,
      if (track.reference != null) track.reference!,
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
                        if (track.reference != null)
                          _placed(
                            viewport.fractionFor(track.reference!),
                            size,
                            width: 90,
                            height: 44,
                            child: _ReferenceMarker(isThai: isThai),
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

/// The customer's own device fix — a labelled dot ("คุณ / You"), the booking-destination
/// stand-in (the v2 booking has no lat/lng; see `GuardTrack.reference`).
class _ReferenceMarker extends StatelessWidget {
  const _ReferenceMarker({required this.isThai});

  final bool isThai;

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
            isThai ? 'คุณ' : 'You',
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

/// En-route / arrived / … chip over the map, straight from the booking lifecycle labels.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.isThai});

  final BookingStatus status;
  final bool isThai;

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
      child: Text(
        isThai
            ? BookingLifecycle.labelTh(status)
            : BookingLifecycle.labelEn(status),
        style: const TextStyle(
            color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
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
              style: const TextStyle(
                  fontSize: 13, color: PgTokens.colorTextMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom card: freshness (LIVE / last-seen), accuracy band, distance-from-you, address +
/// the one-shot refresh gesture.
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
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
    final distance = track.distanceFromReference;
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
              isThai
                  ? 'ห่างจากคุณประมาณ ${formatDistance(distance, thai: true)}'
                  : 'About ${formatDistance(distance, thai: false)} from you',
              style: const TextStyle(
                  fontSize: 12, color: PgTokens.colorTextMuted),
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
