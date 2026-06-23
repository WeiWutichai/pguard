import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_status_controller.dart';
import '../../core/controllers/guard_clock.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/progress_reports_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/models/money.dart';
import '../../core/models/progress_report.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/progress_report_viewer.dart';
import '../../widgets/status_stepper.dart';
import '../call/widgets/call_entry_button.dart';
import '../chat/widgets/chat_entry_button.dart';
import 'cancellation_screen.dart';

/// THE Phase 2 vertical: the customer's live job screen. It watches the booking-status
/// controller, whose state advances from WebSocket PUSH frames — there is NO `Timer.periodic`
/// polling anywhere in this path (v1 polled every 3–5s; that anti-pattern is gone). UI per
/// `Mobile - Customer App.html` / `Mobile - Active Standby.html`.
class LiveStatusScreen extends ConsumerStatefulWidget {
  const LiveStatusScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<LiveStatusScreen> createState() => _LiveStatusScreenState();
}

class _LiveStatusScreenState extends ConsumerState<LiveStatusScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // The live feed is server-PUSH (the WS owned by BookingStatusController). But the
    // api-gateway does not yet proxy WS upgrades (see booking_status_socket.dart — a BACKEND
    // gap), so today the screen would otherwise sit on its one initial snapshot and appear
    // stuck on "finding a guard". Re-pull a fresh snapshot on resume so a status that advanced
    // while backgrounded (accepted → en_route → …) shows; harmless once the WS lands (the push
    // frame is idempotent with the refetched snapshot). Event-driven, NOT a timer.
    if (lifecycle == AppLifecycleState.resumed) {
      ref.invalidate(bookingStatusControllerProvider(widget.bookingId));
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(bookingStatusControllerProvider(widget.bookingId));
    // Await the next snapshot so the spinner holds until the new status lands; the provider
    // state carries any error for the error view, so swallow here.
    try {
      await ref.read(bookingStatusControllerProvider(widget.bookingId).future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(bookingStatusControllerProvider(widget.bookingId));

    return Scaffold(
      appBar: PGuardHeader(
        title: isThai ? 'งานดำเนินอยู่' : 'Live job status',
        showBack: true,
        live: true,
        background: PgTokens.colorGreen800,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // Only surface the server's already-generic message; never leak a raw exception
          // toString() (e.g. a parse TypeError) to the user. Shared hi-fi error state —
          // retry re-runs the snapshot + WS subscribe; no raw booking id on screen.
          error: (e, _) => PgErrorState(
            title: isThai
                ? 'ยังเชื่อมต่อสถานะงานไม่ได้'
                : 'Could not load live status',
            message: e is ApiException
                ? e.message
                : (isThai
                    ? 'ไม่สามารถเชื่อมต่อสถานะงานได้ในขณะนี้'
                    : 'Live status is unavailable right now'),
            onRetry: () => ref
                .invalidate(bookingStatusControllerProvider(widget.bookingId)),
          ),
          data: (booking) => _LiveBody(booking: booking, onRefresh: _refresh),
        ),
      ),
    );
  }
}

class _LiveBody extends StatelessWidget {
  const _LiveBody({required this.booking, required this.onRefresh});

  final Booking booking;
  final Future<void> Function() onRefresh;

  /// The hourly-report section applies once the guard is on site (arrived →
  /// pending_completion → completed) and the booked hours are known.
  bool get _showHourlyReports =>
      (booking.hours ?? 0) > 0 &&
      BookingLifecycle.stepIndex(booking.status) >=
          BookingLifecycle.stepIndex(BookingStatus.arrived);

  @override
  Widget build(BuildContext context) {
    // Pull-to-refresh re-pulls the booking snapshot — the customer's manual way to advance
    // status while the live WS push channel is not yet wired at the gateway (see the screen's
    // lifecycle note). Status still flows by push the moment that backend lands.
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(PgTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Container(
            decoration: BoxDecoration(
              color: PgTokens.colorSurface,
              borderRadius: BorderRadius.circular(PgTokens.radius2xl),
              border: Border.all(color: PgTokens.colorBorder),
            ),
            padding: const EdgeInsets.all(PgTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GuardCard(booking: booking),
                const SizedBox(height: PgTokens.space4),
                // Live-map entry: visible once a guard is assigned and the job is still
                // running (the map screen itself handles every state safely on deep link).
                if (booking.guardId != null &&
                    !BookingLifecycle.isTerminal(booking.status)) ...[
                  _TrackGuardTile(bookingId: booking.id),
                  const SizedBox(height: PgTokens.space4),
                ],
                BookingStatusStepper(status: booking.status),
                const SizedBox(height: PgTokens.space4),
                _Actions(booking: booking),
              ],
            ),
          ),
            if (_showHourlyReports) ...[
              const SizedBox(height: PgTokens.space4),
              _HourlyReportsCard(booking: booking),
            ],
          ],
        ),
      ),
    );
  }
}

/// The design's Active-Job centerpiece: the remaining-time block (while working) + the
/// "รายงานรายชั่วโมง" check-in timeline. Fed by [ProgressReportsController] — re-pulled on
/// every WS status frame, never a timer.
class _HourlyReportsCard extends ConsumerWidget {
  const _HourlyReportsCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(progressReportsControllerProvider(booking.id));
    final progress = async.valueOrNull;
    // Loading/error degrade to nothing — the section appears once reports are readable.
    if (progress == null || progress.bookedHours <= 0) {
      return const SizedBox.shrink();
    }

    final startedAt = progress.workStartedAt;
    final showClock =
        booking.status == BookingStatus.arrived && startedAt != null;

    return Container(
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      padding: const EdgeInsets.all(PgTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showClock) ...[
            _RemainingTimeBlock(
              clock:
                  WorkClock(startedAt: startedAt, hours: progress.bookedHours),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
              child: Divider(height: 1, color: PgTokens.colorBorder),
            ),
          ],
          Text(
            'รายงานรายชั่วโมง · ${progress.reportedCount}/${progress.bookedHours}',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorText),
          ),
          const SizedBox(height: PgTokens.space3),
          for (var hour = 1; hour <= progress.bookedHours; hour++)
            _TimelineItem(
              hour: hour,
              report: progress.reportFor(hour),
              isCurrent: hour == progress.currentHour,
              isLast: hour == progress.bookedHours,
              isThai: isThai,
            ),
        ],
      ),
    );
  }
}

/// The remaining-time block: 74px circular countdown ("02:48" + "เหลือ") beside the booked
/// range, elapsed line and a 7px progress bar. The math is the pure [WorkClock]; the 1s
/// display tick is a [Stream.periodic] re-read (the OTP/PIN house pattern — display only,
/// NOT status polling; status still arrives over the WS).
class _RemainingTimeBlock extends StatelessWidget {
  const _RemainingTimeBlock({required this.clock});

  final WorkClock clock;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _hm(DateTime when) {
    final l = when.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final now = DateTime.now().toUtc();
        final remaining = clock.remaining(now);
        final elapsed = clock.elapsed(now);
        final endsAt = clock.startedAt.add(clock.total);
        return Row(
          children: [
            SizedBox(
              width: 74,
              height: 74,
              child: CustomPaint(
                painter: _CountdownRingPainter(progress: clock.progress(now)),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_two(remaining.inHours)}:${_two(remaining.inMinutes % 60)}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: PgTokens.colorText),
                      ),
                      const Text(
                        'เหลือ',
                        style: TextStyle(
                            fontSize: 10.5, color: PgTokens.colorTextMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: PgTokens.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_hm(clock.startedAt)} – ${_hm(endsAt)} น.',
                    style: const TextStyle(
                        fontSize: 12.5, color: PgTokens.colorTextMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ผ่านไป ${elapsed.inHours} ชม. ${elapsed.inMinutes % 60} นาที',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: PgTokens.space2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 7,
                      child: Stack(
                        children: [
                          Container(color: PgTokens.colorSunken),
                          FractionallySizedBox(
                            widthFactor: clock.progress(now).clamp(0.0, 1.0),
                            child: Container(color: PgTokens.colorPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The 74px countdown ring: full track in border grey, the progressed arc in brand
/// interactive with a round cap, starting at 12 o'clock.
class _CountdownRingPainter extends CustomPainter {
  const _CountdownRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;

    final track = Paint()
      ..color = PgTokens.colorBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..color = PgTokens.colorPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// One vertical-timeline row: a 30px node (done = brand fill + white check; current =
/// 2px brand ring + hour number; pending = grey ring), the check-in time + title, and the
/// "รายงานแล้ว" badge for reported hours. The rail under the node is brand when done.
class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.hour,
    required this.report,
    required this.isCurrent,
    required this.isLast,
    required this.isThai,
  });

  final int hour;
  final ProgressReport? report;
  final bool isCurrent;
  final bool isLast;
  final bool isThai;

  bool get _done => report != null;

  String get _title => hour == 1 ? 'เริ่มงาน' : 'ตรวจรอบ ${hour - 1}';

  String? get _time {
    final r = report;
    if (r == null) return null;
    final l = r.createdAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}';
  }

  Widget _node() {
    if (_done) {
      return Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          color: PgTokens.colorPrimary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 14, color: Colors.white),
      );
    }
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isCurrent ? PgTokens.colorPrimary : PgTokens.colorBorder,
          width: 2,
        ),
      ),
      child: Text(
        '$hour',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: isCurrent ? PgTokens.colorPrimary : PgTokens.colorTextMuted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final time = _time;
    final report = this.report;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            _node(),
            if (!isLast)
              Container(
                width: 2,
                height: 22,
                color: _done ? PgTokens.colorPrimary : PgTokens.colorBorder,
              ),
          ],
        ),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                if (time != null) ...[
                  Text(
                    time,
                    style: const TextStyle(
                        fontSize: 12.5, color: PgTokens.colorTextMuted),
                  ),
                  const SizedBox(width: PgTokens.space2),
                ],
                Expanded(
                  child: Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                // A reported hour opens the submitted photo + GPS + note. The pill carries a
                // small photo glyph so it reads as tappable.
                if (_done)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: PgTokens.colorSuccessBg,
                      borderRadius: BorderRadius.circular(PgTokens.radiusFull),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_outlined,
                            size: 13, color: PgTokens.colorSuccess),
                        const SizedBox(width: 5),
                        Text(
                          isThai ? 'ดูรูป' : 'View',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: PgTokens.colorSuccess,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    if (report == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      onTap: () => showProgressReportViewer(context,
          report: report, isThai: isThai),
      child: row,
    );
  }
}

class _GuardCard extends StatelessWidget {
  const _GuardCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final assigned = booking.guardId != null;
    return Row(
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: PgTokens.colorGreen100,
          child: Icon(
            assigned ? Icons.shield_outlined : Icons.search,
            color: PgTokens.colorGreen800,
            size: 20,
          ),
        ),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assigned
                    ? 'เจ้าหน้าที่รักษาความปลอดภัย'
                    : 'กำลังค้นหาเจ้าหน้าที่',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Text(
                booking.address ?? 'pguard',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: PgTokens.colorTextMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.booking});

  final Booking booking;

  /// The cancellable window, exactly per the contract (`cancelBooking` in
  /// booking.yaml): PRE-ARRIVAL only — `requested`/`accepted`/`en_route`.
  static const Set<BookingStatus> _cancellable = {
    BookingStatus.requested,
    BookingStatus.accepted,
    BookingStatus.enRoute,
  };

  /// Display total in satang for the cancellation screen's refund banner; `null` when
  /// the server-owned rate isn't known yet (the banner then omits the amount).
  int? get _totalSatang {
    final baseFeeSatang = Money.satangFromString(booking.baseFee);
    final hours = booking.hours ?? 0;
    if (baseFeeSatang <= 0 || hours <= 0) return null;
    return Money.total(
      baseFeeSatang: baseFeeSatang,
      hours: hours,
      guardCount: booking.guardCount ?? 1,
      tipSatang: Money.satangFromString(booking.tip),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final canCancel = _cancellable.contains(booking.status);
    final myUserId = ref.watch(sessionProvider).user?.userId;
    return Row(
      children: [
        // Customer ↔ assigned guard. Enabled once a guard is assigned (guard_id present).
        ChatEntryButton(
          requestId: booking.id,
          requestStatus: booking.status.wire,
          acting: ChatRole.customer,
          myUserId: myUserId,
          counterpartUserId: booking.guardId,
        ),
        const SizedBox(width: PgTokens.space2),
        // Customer → assigned guard call (audio/video). Enabled ONLY while the booking is callable
        // (accepted/en_route/arrived + guard assigned) — matching the calling service, so the
        // button is never live for a status the server would 409 (e.g. pendingCompletion).
        CallEntryButton(
          bookingId: booking.id,
          enabled: booking.guardId != null &&
              BookingLifecycle.isCallable(booking.status),
        ),
        const SizedBox(width: PgTokens.space2),
        Expanded(
          // Pre-arrival the design's cancel affordance is a GHOST (outline) button, not a
          // filled danger block. It opens the cancellation flow, passing what this screen
          // already knows (address + display total) so the header/banner render instantly.
          child: canCancel
              ? SizedBox(
                  height: 52,
                  child: TextButton(
                    onPressed: () => context.push(
                      '/booking/${booking.id}/cancel',
                      extra: CancellationArgs(
                        address: booking.address,
                        totalSatang: _totalSatang,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: PgTokens.colorDanger,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                        side: const BorderSide(color: PgTokens.colorBorder),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isThai ? 'ยกเลิกและค้นหาใหม่' : 'Cancel & search again',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                )
              // Once the job is completed, the design's next step is the customer review
              // (Customer App ⑫). One review per assignment — a duplicate is handled by the
              // review screen (409 → "already reviewed").
              : booking.status == BookingStatus.completed
                  ? PgPrimaryButton(
                      label: isThai ? 'ให้คะแนนเจ้าหน้าที่' : 'Rate the guard',
                      color: PgTokens.colorAmber500,
                      onPressed: () =>
                          context.push('/booking/${booking.id}/review'),
                    )
                  : PgPrimaryButton(
                      label: isThai ? 'ดูรายละเอียด' : 'Details',
                      onPressed: () {},
                    ),
        ),
      ],
    );
  }
}

/// Opens the customer live-map (`/booking/{id}/map`) — guard marker + status, pushed by the
/// booking-status WebSocket (no polling).
class _TrackGuardTile extends ConsumerWidget {
  const _TrackGuardTile({required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Material(
      color: PgTokens.colorGreen50,
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      child: InkWell(
        onTap: () => context.push('/booking/$bookingId/map'),
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: PgTokens.space3, vertical: PgTokens.space3),
          child: Row(
            children: [
              const Icon(Icons.map_outlined,
                  size: 20, color: PgTokens.colorGreen800),
              const SizedBox(width: PgTokens.space2),
              Expanded(
                child: Text(
                  isThai ? 'ดูตำแหน่งเจ้าหน้าที่' : 'Track guard',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorGreen800,
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18,
                  color: PgTokens.colorGreen800.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
