import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_payment_controller.dart';
import '../../core/controllers/booking_status_controller.dart';
import '../../core/controllers/customer_home_controller.dart';
import '../../core/controllers/customer_public_profile_controller.dart';
import '../../core/controllers/guard_clock.dart';
import '../../core/controllers/guard_earnings_controller.dart';
import '../../core/controllers/guard_location_controller.dart';
import '../../core/controllers/guard_public_profile_controller.dart';
import '../../core/controllers/guard_route_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/my_review_controller.dart';
import '../../core/controllers/progress_reports_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/models/money.dart';
import '../../core/models/progress_report.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/booking_status_pill.dart';
import '../../widgets/booking_status_timeline.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/pg_network_image.dart';
import '../../widgets/pg_skeleton.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/progress_report_viewer.dart';
import '../../widgets/status_stepper.dart';
import '../call/widgets/call_entry_button.dart';
import '../chat/widgets/chat_entry_button.dart';
import 'cancellation_screen.dart';
import 'guard_map_screen.dart';
import 'widgets/cancel_reason.dart';
import 'widgets/job_receipt_sheet.dart';
import 'widgets/travel_map_preview.dart';

/// The customer's response to a guard withdrawing a paid job (E): re-search for a new guard, or
/// cancel the job outright.
enum _GuardWithdrewChoice { research, cancel }

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
  /// E latch: the guard-withdrew (`declined`) choice dialog fires AT MOST ONCE. `declined` is
  /// terminal so no further frames follow, but this also stops a spurious rebuild re-showing it.
  bool _declineDialogShown = false;

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
    // The live feed is server-PUSH (the WS owned by BookingStatusController) and the gateway DOES
    // proxy /v1/ws/bookings/{id} now. While backgrounded the socket can drop, so re-pull a fresh
    // snapshot on resume to catch any status that advanced (accepted → en_route → …) — a
    // belt-and-suspenders for the WS, not a substitute. The push frame is idempotent with the
    // refetched snapshot. Event-driven, NOT a timer.
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

  /// E: a guard WITHDREW after accepting (booking → `declined`) is NOT a dead end for the customer —
  /// but silently bouncing them into discovery hid what happened. Instead NOTIFY + offer a CHOICE:
  /// find a new guard (re-search) or cancel the job outright. Fires at most once
  /// ([_declineDialogShown]); the dialog is deferred to a post-frame callback so it never runs
  /// mid-build / mid-notification. Gated by the caller strictly on `status == declined` so a
  /// `cancelled` booking (including the result of choosing "cancel" below) never re-triggers it.
  void _promptGuardWithdrew() {
    if (_declineDialogShown) return;
    _declineDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showGuardWithdrewDialog();
    });
  }

  Future<void> _showGuardWithdrewDialog() async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final choice = await showDialog<_GuardWithdrewChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(isThai ? 'รปภ. ยกเลิกงาน' : 'The guard cancelled'),
        content: Text(
          isThai
              ? 'เจ้าหน้าที่ยกเลิกงานนี้ คุณต้องการค้นหาเจ้าหน้าที่ใหม่ หรือยกเลิกงาน?'
              : 'The guard withdrew from this job. Find a new guard, or cancel the job?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_GuardWithdrewChoice.cancel),
            child: Text(isThai ? 'ยกเลิกงาน' : 'Cancel job'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_GuardWithdrewChoice.research),
            child: Text(isThai ? 'ค้นหา Guard ใหม่' : 'Find a new guard'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == _GuardWithdrewChoice.research) {
      // Re-search: the shared keepAlive [BookingFlowController] still holds the service/place/time,
      // so discovery recreates the SAME job — and its live screen subscribes to the NEW booking's WS,
      // so notifications follow the new job. Rebuild a poppable home→discovery stack (mirrors
      // guard_discovery's _confirm) so back lands on the dashboard, not a dead route.
      context.go('/home/customer');
      context.push('/book/guards');
    } else if (choice == _GuardWithdrewChoice.cancel) {
      // Cancel outright: declined → cancelled (full refund). Fold the returned booking into state and
      // STAY on the now-terminal cancelled screen — the refund banner covers it. The strict
      // `== declined` gate above then keeps this cancelled booking from ever re-prompting.
      final error = await ref
          .read(bookingStatusControllerProvider(widget.bookingId).notifier)
          .cancelAfterDecline();
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    }
    // choice == null (dismissed, e.g. hardware back) → stay on the live screen; the latch prevents a
    // re-prompt on rebuild.
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(bookingStatusControllerProvider(widget.bookingId));

    // E: watch for the transition INTO `declined` (a guard withdrew a PAID job) — however the frame
    // lands (the WS push folded by the controller, or an initial snapshot that is already declined)
    // it flows through this provider — and PROMPT the customer with a choice (find a new guard, or
    // cancel the job). This is DISTINCT from `cancelled` (the customer's OWN cancel, or the result of
    // choosing "cancel" here), which STAYS terminal on the refund banner and NEVER re-prompts — the
    // strict `== declined` gate kills the re-entry loop. Registered in build (Riverpod dedupes across
    // rebuilds); the prompt itself is latched to fire at most once.
    ref.listen(bookingStatusControllerProvider(widget.bookingId), (_, next) {
      if (next.valueOrNull?.status == BookingStatus.declined) {
        _promptGuardWithdrew();
      }
    });

    // D: the header must reflect the booking's real state — a completed / terminal job is NOT "live".
    // Show a completed/cancelled title and drop the pulsing LIVE badge once the booking is terminal
    // (it kept saying "งานดำเนินอยู่ / Live" on a finished job). While loading (booking null) keep the
    // live title — the snapshot lands in a beat.
    final booking = async.valueOrNull;
    final isTerminal =
        booking != null && BookingLifecycle.isTerminal(booking.status);
    // `booking` is promoted non-null in this branch (isTerminal implies booking != null).
    final headerTitle = !isTerminal
        ? (isThai ? 'งานดำเนินอยู่' : 'Live job status')
        : (booking.status == BookingStatus.completed
            ? (isThai ? 'งานเสร็จสิ้น' : 'Job completed')
            : (isThai ? 'งานที่ยกเลิก' : 'Job cancelled'));

    return Scaffold(
      appBar: PGuardHeader(
        title: headerTitle,
        showBack: true,
        // FROZEN-BACK GUARD: this screen is usually the navigator ROOT — the booking flow
        // (guard_discovery), payment success and the PromptPay panel all `context.go` HERE, which
        // REPLACES the stack. The default header back (`maybePop`) then has nothing to pop and
        // silently does nothing, so once a guard cancelled the job the customer was stranded on the
        // dead live screen and had to force-close the app. Pop when there IS a stack; otherwise fall
        // back to the customer home so back is never a no-op.
        onBack: () =>
            context.canPop() ? context.pop() : context.go('/home/customer'),
        // D: pulse LIVE only while the job is actually live (hidden once terminal/completed).
        live: !isTerminal,
        background: PgTokens.colorGreen800,
      ),
      // Stale-while-revalidate (perf-review #1/#10): the header shell above already renders from
      // `valueOrNull`; the body shows the LAST-KNOWN snapshot on re-entry and a skeleton (status pill
      // + timeline placeholders) on a first load rather than a blank spinner while the snapshot lands
      // and the WS subscribes. The error state shows only when there is no snapshot at all.
      body: SafeArea(
        child: booking != null
            ? _LiveBody(booking: booking, onRefresh: _refresh)
            : (async.hasError
                // Only surface the server's already-generic message; never leak a raw exception
                // toString() (e.g. a parse TypeError). Shared hi-fi error state — retry re-runs the
                // snapshot + WS subscribe; no raw booking id on screen.
                ? PgErrorState(
                    title: isThai
                        ? 'ยังเชื่อมต่อสถานะงานไม่ได้'
                        : 'Could not load live status',
                    message: async.error is ApiException
                        ? (async.error as ApiException).message
                        : (isThai
                            ? 'ไม่สามารถเชื่อมต่อสถานะงานได้ในขณะนี้'
                            : 'Live status is unavailable right now'),
                    onRetry: () => ref.invalidate(
                        bookingStatusControllerProvider(widget.bookingId)),
                  )
                : const _LiveStatusSkeleton()),
      ),
    );
  }
}

/// First-load skeleton for the live-status body (perf-review #10): a status-pill placeholder over
/// a couple of card placeholders, so the screen shows its shape while the snapshot lands + the WS
/// subscribes, instead of a blank spinner.
class _LiveStatusSkeleton extends StatelessWidget {
  const _LiveStatusSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(PgTokens.space4),
      children: const [
        Center(
          child: PgSkeletonBox(
              width: 150, height: 28, radius: PgTokens.radiusFull),
        ),
        SizedBox(height: PgTokens.space4),
        PgSkeletonCard(height: 120),
        SizedBox(height: PgTokens.space3),
        PgSkeletonCard(height: 88),
        SizedBox(height: PgTokens.space3),
        PgSkeletonCard(height: 160),
      ],
    );
  }
}

class _LiveBody extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // PAY GATE OWNERSHIP (#87): this is the CUSTOMER's live screen, but a guard can also reach it
    // (e.g. the active-job screen's "ดูสถานะสด/View live status" ghost button deep-links here).
    // ONLY the booking's owner (the customer) may ever see the "ชำระเงิน/Pay" CTA — a guard must
    // NEVER see a pay button. Compare the acting user (from the session) to the booking's
    // customer_id; everything pay-related below is gated on this.
    final viewerUserId = ref.watch(sessionProvider).user?.userId;
    final isOwner = viewerUserId != null && viewerUserId == booking.customerId;
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
                  // Live-map: while a guard is assigned and the job is running, embed an inline
                  // preview (guard pin + destination + straight route) in the empty space below the
                  // card — tap / expand opens the full-screen map. The map screen itself handles
                  // every state safely on deep link.
                  if (booking.guardId != null &&
                      !BookingLifecycle.isTerminal(booking.status)) ...[
                    _InlineGuardMap(bookingId: booking.id),
                    const SizedBox(height: PgTokens.space4),
                  ],
                  BookingStatusStepper(status: booking.status),
                  // #123: the shared vertical step timeline of the guard's progress for THIS booking
                  // (accept → en route → arrived → working → completed). Shown the instant a guard is
                  // assigned (a guard_id exists) — before that there is no progress to track. The same
                  // widget renders on the guard's active-job screen. Driven purely by the booking
                  // status the WS pushes — no timer.
                  if (booking.guardId != null) ...[
                    const SizedBox(height: PgTokens.space4),
                    _StatusTimelineSection(
                        status: booking.status, bookingId: booking.id),
                  ],
                  // A PAID booking that DIED (guard withdrew → declined, or cancelled): the backend
                  // queued a full refund, but no screen told the customer — apparent silent money
                  // limbo (deep-review). Reassure them their money is coming back.
                  if (isOwner &&
                      booking.isPaid &&
                      BookingLifecycle.isNegativeTerminal(booking.status)) ...[
                    const SizedBox(height: PgTokens.space4),
                    const _RefundComingBanner(),
                  ],
                  const SizedBox(height: PgTokens.space4),
                  // PRE-PAY: the instant a guard ACCEPTS, the CUSTOMER pays the server-computed
                  // estimate. This is the prominent CTA into the PaymentScreen; it shows only while
                  // accepted-and-unpaid (the booking-status WS drives `status`/`paid_at`, no polling)
                  // — once paid, the booking un-gates the guard and this disappears.
                  // OWNER-ONLY (#87): only the booking's customer ever sees the Pay button. A guard
                  // who reaches this screen sees a READ-ONLY "รอลูกค้าชำระเงิน" notice instead —
                  // never a pay action.
                  if (booking.status == BookingStatus.accepted &&
                      !booking.isPaid) ...[
                    if (isOwner)
                      _PayNowBanner(bookingId: booking.id)
                    else
                      const _AwaitingCustomerPaymentNotice(),
                    const SizedBox(height: PgTokens.space4),
                  ],
                  // The guard has REQUESTED completion (arrived → pending_completion). The
                  // customer must rule on it: APPROVE → completed (triggers the settle) or
                  // REJECT → back to arrived (the guard keeps working). Driven by the WS status
                  // frame, no polling.
                  if (booking.status == BookingStatus.pendingCompletion) ...[
                    _CompletionReviewPanel(bookingId: booking.id),
                    const SizedBox(height: PgTokens.space4),
                  ],
                  _Actions(booking: booking, isOwner: isOwner),
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
      onTap: () =>
          showProgressReportViewer(context, report: report, isThai: isThai),
      child: row,
    );
  }
}

class _GuardCard extends ConsumerWidget {
  const _GuardCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final guardId = booking.guardId;
    final assigned = guardId != null;
    // #123: show the assigned guard's REAL NAME (from the same IDOR-gated `/guards/{id}/public`
    // read the live map uses) rather than a generic role label. Enrichment only — while it loads
    // or if it degrades (403/404/5xx → null), we fall back to the role label, never a fabricated
    // name. Watched only when a guard is assigned.
    final profile = assigned
        ? ref.watch(guardPublicProfileProvider(guardId)).valueOrNull
        : null;
    final name = profile?.fullName?.trim();
    final avatarUrl = profile?.avatarUrl;
    final title = !assigned
        ? (isThai ? 'กำลังค้นหาเจ้าหน้าที่' : 'Finding a guard')
        : (name != null && name.isNotEmpty)
            ? name
            : (isThai ? 'เจ้าหน้าที่รักษาความปลอดภัย' : 'Security guard');
    // #163: the assigned guard's real PHOTO (the same IDOR-gated /guards/{id}/public read), falling
    // back to the shield while it loads or if it 404s/errors — never a broken-image box.
    final Widget guardAvatar = CircleAvatar(
      radius: 21,
      backgroundColor: PgTokens.colorGreen100,
      child: Icon(
        assigned ? Icons.shield_outlined : Icons.search,
        color: PgTokens.colorGreen800,
        size: 20,
      ),
    );
    return Row(
      children: [
        if (avatarUrl == null)
          guardAvatar
        else
          // Tap the guard's picture to see it full-screen.
          Semantics(
            button: true,
            label: isThai ? 'ดูรูปโปรไฟล์' : 'View profile picture',
            child: GestureDetector(
              onTap: () =>
                  showImageViewer(context, url: avatarUrl, isThai: isThai),
              child: PgNetworkImage(
                url: avatarUrl,
                width: 42,
                height: 42,
                borderRadius: BorderRadius.circular(21),
                placeholder: guardAvatar,
                errorWidget: guardAvatar,
              ),
            ),
          ),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

/// The #123 status-timeline section on the customer live screen: a titled card-internal block
/// wrapping the shared [BookingStatusTimeline]. The booking stays wire-status `arrived` the WHOLE
/// time the guard works, so the "Working" step is DERIVED: it ticks once the guard files the START
/// (hour-1) check-in. The customer learns that from [HourlyProgress.workStartedAt] (the earliest
/// check-in anchor) — the SAME source the countdown card uses, refreshed LIVE by the
/// `progress_reported` WS nudge — so the timeline flips arrived→Working in realtime, no longer
/// waiting for the booking to move past `arrived`. The same widget renders on the guard's screen.
class _StatusTimelineSection extends ConsumerWidget {
  const _StatusTimelineSection({required this.status, required this.bookingId});

  final BookingStatus status;
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    // Same provider instance the countdown card watches (family-keyed by bookingId) → no extra
    // fetch. Non-null once ≥1 check-in exists (the hour-1 start check-in); empty/error → false.
    final started = ref
            .watch(progressReportsControllerProvider(bookingId))
            .valueOrNull
            ?.workStartedAt !=
        null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isThai ? 'สถานะการทำงาน' : 'Job progress',
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: PgTokens.colorText),
        ),
        const SizedBox(height: PgTokens.space3),
        BookingStatusTimeline(status: status, isThai: isThai, started: started),
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.booking, required this.isOwner});

  final Booking booking;

  /// Whether the acting viewer is the booking's CUSTOMER (owner). Drives the rating CTA: ONLY the
  /// customer rates the guard (#97) — a guard who reaches this screen for their own job must NEVER
  /// see a "rate the guard" action; they get a neutral completion state + the receipt instead.
  final bool isOwner;

  /// Display total in satang for the cancellation screen's refund banner + the booking-details
  /// sheet; `null` when the server-owned rate isn't known yet (callers then omit the amount).
  /// Shared with the guard's active-job details sheet via [Booking.displayTotalSatang] so the two
  /// never drift.
  int? get _totalSatang => booking.displayTotalSatang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final canCancel = BookingLifecycle.isCancellable(booking.status);
    final myUserId = ref.watch(sessionProvider).user?.userId;
    final isCompleted = booking.status == BookingStatus.completed;

    // Customer ↔ assigned guard. Chat is enabled once a guard is assigned (guard_id present) and
    // stays reachable after completion (chat-after-completion). Call is enabled only while the
    // booking is callable (accepted/en_route/arrived/pending_completion + guard assigned) — matching
    // the calling service, so it is never live for a status the server would 409 (the terminals).
    final chat = ChatEntryButton(
      requestId: booking.id,
      requestStatus: booking.status.wire,
      acting: ChatRole.customer,
      myUserId: myUserId,
      counterpartUserId: booking.guardId,
    );
    final call = CallEntryButton(
      bookingId: booking.id,
      enabled: booking.guardId != null &&
          BookingLifecycle.isCallable(booking.status),
    );

    // COMPLETED: the completion actions get their OWN full-width row BELOW the chat/call icons so
    // their labels render at the normal CTA size (16.5 w600). Cramming rate + receipt into the
    // trailing slot beside the two icon buttons squeezed them so narrow the labels shrank to an
    // illegible size (the reported "tiny button text"). The OWNER (customer) rates the guard (Customer
    // App ⑫) + views the receipt; a guard who deep-links here for their own job gets their earnings
    // instead — #97: rating is CUSTOMER-ONLY, and the receipt is the customer's document (it totals
    // their bill + tip + crew and settles against their payment, which a guard cannot read).
    // [_RateGuardButton] gates its CTA on whether the customer has ALREADY reviewed
    // (GET /assignments/{id}/review) so a re-open shows a passive "rated" state instead of
    // re-entering the form; the receipt stays reachable beside it either way.
    if (isCompleted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [chat, const SizedBox(width: PgTokens.space2), call]),
          const SizedBox(height: PgTokens.space2),
          if (isOwner)
            Row(
              children: [
                Expanded(child: _RateGuardButton(bookingId: booking.id)),
                const SizedBox(width: PgTokens.space2),
                Expanded(child: _ViewReceiptButton(booking: booking)),
              ],
            )
          else
            const _MyEarningsButton(),
        ],
      );
    }

    return Row(
      children: [
        chat,
        const SizedBox(width: PgTokens.space2),
        call,
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
              // Otherwise (in-flight, not yet cancellable: en_route/arrived/pending) the trailing
              // action opens the booking-details sheet (address / schedule / hours / guards / price).
              : PgPrimaryButton(
                  label: isThai ? 'ดูรายละเอียด' : 'Details',
                  onPressed: () => showBookingDetailsSheet(
                    context,
                    booking: booking,
                    totalSatang: _totalSatang,
                    isThai: isThai,
                    // Same "Working" signal as the main timeline (the hour-1 check-in).
                    started: ref
                            .read(progressReportsControllerProvider(booking.id))
                            .valueOrNull
                            ?.workStartedAt !=
                        null,
                  ),
                ),
        ),
      ],
    );
  }
}

/// The customer's completion CTA for a `completed` booking: "Rate the guard" when they have NOT
/// reviewed yet, or a passive "ให้คะแนนแล้ว/Rated" state once they have. Gated on
/// [myReviewProvider] (`GET /assignments/{id}/review`) so re-opening a completed booking no longer
/// re-offers the form and dead-ends on the submit 409 (the reported "can rate again" bug). While the
/// rated-state is unknown (loading/error) it optimistically offers the form — the review screen
/// re-checks on entry, and the server's one-per-assignment 409 is the final backstop.
class _RateGuardButton extends ConsumerWidget {
  const _RateGuardButton({required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    // Already reviewed only when the fetch resolved to a non-null review; loading/error/404 → not
    // yet (offer the form). `.valueOrNull` is null in all of those "not confirmed rated" cases.
    final alreadyRated =
        ref.watch(myReviewProvider(bookingId)).valueOrNull != null;

    if (alreadyRated) {
      // Passive "rated" state — no navigation into the form. A tap just reassures the customer.
      return PgPrimaryButton(
        label: isThai ? 'ให้คะแนนแล้ว' : 'Rated',
        color: PgTokens.colorGreen700,
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isThai
                ? 'คุณให้คะแนนงานนี้แล้ว ขอบคุณสำหรับรีวิว'
                : "You've already rated this job. Thanks for your review!"),
          ),
        ),
      );
    }
    return PgPrimaryButton(
      label: isThai ? 'ให้คะแนนเจ้าหน้าที่' : 'Rate the guard',
      color: PgTokens.colorAmber500,
      onPressed: () => context.push('/booking/$bookingId/review'),
    );
  }
}

/// The CUSTOMER's "ดูใบสรุป/View receipt" action, opening the shared [showJobReceiptSheet] for a
/// completed booking. Owner-only by construction: the receipt is settled against the customer's own
/// `GET /v1/payments` row, which nobody else can read.
class _ViewReceiptButton extends ConsumerWidget {
  const _ViewReceiptButton({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final payment =
        ref.watch(bookingPaymentControllerProvider(booking.id)).valueOrNull;
    return PgPrimaryButton(
      label: isThai ? 'ดูใบสรุปค่าบริการ' : 'View receipt',
      color: PgTokens.colorGreen700,
      onPressed: () => showJobReceiptSheet(
        context,
        booking: booking,
        payment: payment,
        isThai: isThai,
      ),
    );
  }
}

/// The guard's counterpart to the customer's receipt: their own pay, not the customer's bill.
class _MyEarningsButton extends ConsumerWidget {
  const _MyEarningsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return PgPrimaryButton(
      label: isThai ? 'ดูรายได้ของฉัน' : 'My earnings',
      color: PgTokens.colorGreen700,
      onPressed: () => context.push('/earnings'),
    );
  }
}

/// The completion-review panel — shown while the booking is `pending_completion` (the guard has
/// requested completion). The customer APPROVES ("ยืนยันจบงาน" → `completed`, which triggers the
/// server-side settle/reconcile and routes to the job-completion summary) or REJECTS ("ให้ทำต่อ"
/// → back to `arrived`, the guard keeps working; a snackbar confirms and the screen stays). Both
/// hit `PUT /v1/bookings/{id}/review-completion { action }` via [BookingStatusController].
class _CompletionReviewPanel extends ConsumerStatefulWidget {
  const _CompletionReviewPanel({required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<_CompletionReviewPanel> createState() =>
      _CompletionReviewPanelState();
}

class _CompletionReviewPanelState
    extends ConsumerState<_CompletionReviewPanel> {
  bool _busy = false;

  Future<void> _review({required bool approve}) async {
    if (_busy) return;
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    setState(() => _busy = true);
    final error = await ref
        .read(bookingStatusControllerProvider(widget.bookingId).notifier)
        .reviewCompletion(approve: approve);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (approve) {
      // The booking just moved to `completed`, so the customer home's one-shot `GET /bookings`
      // snapshot (the "งานที่กำลังดำเนิน" ongoing-job card) is now stale. Invalidate it here so it
      // re-pulls the moment the customer lands back on home — home does NOT observe the booking-
      // status WS, so without this it stays stale until pull-to-refresh / app resume.
      ref.invalidate(customerHomeControllerProvider);
      // G: the completion also lands the guard-earnings settle (booking.completed → payment
      // reconcile). Invalidate the guard's settle rows so any guard-earnings screen refetches the
      // reconciled hours/commission when it lands (best-effort: a no-op on the customer's own
      // device where that provider isn't mounted).
      ref.invalidate(guardEarningsRowsProvider);
      // Settle is in flight (booking.completed → payment reconcile). Move to the summary; it
      // reads the reconciled payment and forces the customer on to rate the guard.
      context.pushReplacement('/booking/${widget.bookingId}/summary');
    } else {
      // Rejected → back to `arrived`; the guard continues. Stay on the live screen (the WS
      // `arrived` frame the server emits is idempotent with the folded state).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isThai
              ? 'แจ้งให้เจ้าหน้าที่ทำงานต่อแล้ว'
              : 'Asked the guard to continue'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorAmber50,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        border: Border.all(color: PgTokens.colorAmber200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined,
                  size: 18, color: PgTokens.colorAmber700),
              const SizedBox(width: PgTokens.space2),
              Expanded(
                child: Text(
                  isThai ? 'รอยืนยันจบงาน' : 'Awaiting your confirmation',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: PgTokens.space2),
          Text(
            isThai
                ? 'เจ้าหน้าที่แจ้งว่างานเสร็จแล้ว — กรุณายืนยันเพื่อจบงาน หรือให้ทำงานต่อ'
                : 'The guard has marked the job done. Confirm to finish, or ask them to '
                    'keep working.',
            style:
                const TextStyle(fontSize: 12.5, color: PgTokens.colorTextMuted),
          ),
          const SizedBox(height: PgTokens.space4),
          PgPrimaryButton(
            label: isThai ? 'ยืนยันจบงาน' : 'Confirm completion',
            color: PgTokens.colorAmber500,
            foreground: PgTokens.colorOnAmber,
            busy: _busy,
            onPressed: _busy ? null : () => _review(approve: true),
          ),
          const SizedBox(height: PgTokens.space2),
          SizedBox(
            height: 52,
            child: TextButton(
              onPressed: _busy ? null : () => _review(approve: false),
              style: TextButton.styleFrom(
                foregroundColor: PgTokens.colorText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                  side: const BorderSide(color: PgTokens.colorBorder),
                ),
              ),
              child: Text(
                isThai ? 'ให้ทำต่อ' : 'Keep working',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One parsed line of the composed booking `address`: an icon, a bilingual label and the value.
/// The first address line carries [isPrimary] = true (rendered as the "ที่อยู่/Address" row);
/// each folded "label: value" line becomes its own row with a fitting icon.
class AddressDetail {
  const AddressDetail({
    required this.icon,
    required this.label,
    required this.value,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isPrimary;
}

/// Parse the composed booking `address` (as built by `composeAddress`) back into discrete detail
/// rows. The address is a `\n`-joined string: the FIRST non-empty line is the real site address;
/// each subsequent line is a "label: value" pair the booking form folded in (place type / extra
/// details / equipment / add-ons). Both TH and EN label prefixes are matched. Any line that does
/// NOT match a known prefix is kept under a generic "เพิ่มเติม/More" row so nothing is dropped.
/// Pure → unit-testable; [isThai] only chooses which label text the rows carry.
///
/// Returns an empty list for a null/blank address (the sheet then shows the "Not set" fallback).
List<AddressDetail> parseComposedAddress(String? address,
    {required bool isThai}) {
  if (address == null) return const [];
  final lines = address
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return const [];

  // (icon, TH prefix, EN prefix, TH row label, EN row label) for each folded line kind.
  const folded = <(IconData, String, String, String, String)>[
    (
      Icons.home_outlined,
      'ประเภทสถานที่',
      'Place type',
      'ประเภทสถานที่',
      'Place type'
    ),
    (
      Icons.notes_outlined,
      'รายละเอียดเพิ่มเติม',
      'Details',
      'รายละเอียดเพิ่มเติม',
      'Details'
    ),
    (Icons.security_outlined, 'อุปกรณ์', 'Equipment', 'อุปกรณ์', 'Equipment'),
    (
      Icons.add_circle_outline,
      'บริการเพิ่มเติม',
      'Add-ons',
      'บริการเพิ่มเติม',
      'Add-ons'
    ),
  ];

  final out = <AddressDetail>[
    AddressDetail(
      icon: Icons.place_outlined,
      label: isThai ? 'ที่อยู่' : 'Address',
      value: lines.first,
      isPrimary: true,
    ),
  ];

  for (final line in lines.skip(1)) {
    final colon = line.indexOf(':');
    final prefix = colon < 0 ? line : line.substring(0, colon).trim();
    final value = colon < 0 ? line : line.substring(colon + 1).trim();
    final match =
        folded.where((f) => f.$2 == prefix || f.$3 == prefix).toList();
    if (colon >= 0 && match.isNotEmpty) {
      final f = match.first;
      out.add(AddressDetail(
        icon: f.$1,
        label: isThai ? f.$4 : f.$5,
        value: value.isEmpty ? '—' : value,
      ));
    } else {
      // Unknown folded line — keep it so the sheet stays COMPLETE.
      out.add(AddressDetail(
        icon: Icons.info_outline,
        label: isThai ? 'เพิ่มเติม' : 'More',
        value: line,
      ));
    }
  }
  return out;
}

/// The booking-details bottom sheet behind the live screen's "ดูรายละเอียด/Details" action.
/// The composed `address` is PARSED back into discrete rows (real address + place type / extra
/// details / equipment / add-ons), then schedule, hours, guards, the assigned-guard ref, tip,
/// payment state, status and the display total. Read-only; the figures come from the live booking
/// snapshot. The body scrolls so a long, fully-detailed sheet never overflows.
Future<void> showBookingDetailsSheet(
  BuildContext context, {
  required Booking booking,
  required int? totalSatang,
  required bool isThai,
  // #127: when the GUARD opens this sheet (their active-job card), show a "ลูกค้า / Customer" row
  // resolving the customer's REAL NAME (the IDOR-gated `/customers/{id}/public` read). The CUSTOMER
  // viewing their own booking never sees it (it would be their own name) → defaults off.
  bool showCustomer = false,
  // Whether the guard has STARTED working (the hour-1 check-in is filed), so the sheet's timeline
  // ticks "Working" in LOCK-STEP with the live screen. A plain function can't watch a provider, so
  // the (Consumer) caller passes the SAME signal it feeds the main timeline (`progress.workStartedAt
  // != null`) — never `booking.workStartedAt` (stamped at Start, before the check-in) which would
  // make the sheet flip Working while the main screen still shows Arrived.
  bool started = false,
}) {
  String two(int n) => n.toString().padLeft(2, '0');
  String? schedule;
  final s = booking.scheduledAt?.toLocal();
  if (s != null) {
    schedule =
        '${s.day}/${two(s.month)}/${s.year}  ${two(s.hour)}:${two(s.minute)}${isThai ? ' น.' : ''}';
  }
  final hours = booking.hours;
  final guards = booking.guardCount;
  final addressRows = parseComposedAddress(booking.address, isThai: isThai);
  final tipSatang = Money.satangFromString(booking.tip);
  // WHY the booking ended, for whichever side is reading this sheet: the customer sees the
  // guard's decline reason, the guard (showCustomer) sees the customer's cancel reason. Only
  // meaningful on a negative terminal, and empty for a pre-migration booking that stored no code
  // — either way the sheet just omits the rows.
  final cancelReason = BookingLifecycle.isNegativeTerminal(booking.status)
      ? PgCancelReason.labelFor(booking.cancellationReason, isThai)
      : '';
  final cancelNote = booking.cancellationNote?.trim();

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: PgTokens.colorSurface,
    showDragHandle: true,
    // Allow the sheet to grow + scroll for a fully-detailed booking.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(PgTokens.radius2xl)),
    ),
    builder: (context) {
      return SafeArea(
        child: ConstrainedBox(
          // Cap at most of the screen; the inner scroll view handles overflow.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                PgTokens.space5, 0, PgTokens.space5, PgTokens.space5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isThai ? 'รายละเอียดการจอง' : 'Booking details',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: PgTokens.space4),
                // The address rows: the real site address first, then each folded line
                // (place type / details / equipment / add-ons) as its own row.
                if (addressRows.isEmpty)
                  _DetailRow(
                    icon: Icons.place_outlined,
                    label: isThai ? 'ที่อยู่' : 'Address',
                    value: isThai ? 'ไม่ระบุ' : 'Not set',
                  )
                else
                  for (final d in addressRows)
                    _DetailRow(icon: d.icon, label: d.label, value: d.value),
                if (schedule != null)
                  _DetailRow(
                    icon: Icons.event_outlined,
                    label: isThai ? 'นัดหมาย' : 'Scheduled',
                    value: schedule,
                  ),
                if (hours != null)
                  _DetailRow(
                    icon: Icons.schedule_outlined,
                    label: isThai ? 'จำนวนชั่วโมง' : 'Hours',
                    value: '$hours',
                  ),
                if (guards != null)
                  _DetailRow(
                    icon: Icons.groups_outlined,
                    label: isThai ? 'จำนวนเจ้าหน้าที่' : 'Guards',
                    value: '$guards',
                  ),
                // #127: the GUARD-only customer row — resolves the customer's REAL NAME (the
                // IDOR-gated `/customers/{id}/public` read) so the guard addresses them by name, not
                // a raw id. Only shown when [showCustomer] (the guard's active-job card); a customer
                // viewing their own booking never sees it. Degrades to a short `#id` ref.
                if (showCustomer)
                  _CustomerDetailRow(
                      customerId: booking.customerId, isThai: isThai),
                // #123: show the assigned guard's REAL NAME (resolved from the IDOR-gated
                // `/guards/{id}/public` read). While it loads / if it degrades it falls back to a
                // short id ref so the customer can still quote the guard (e.g. in support / chat).
                if (booking.guardId != null)
                  _GuardDetailRow(guardId: booking.guardId!, isThai: isThai),
                if (tipSatang > 0)
                  _DetailRow(
                    icon: Icons.volunteer_activism_outlined,
                    label: isThai ? 'ทิป' : 'Tip',
                    value: Money.format(tipSatang, decimals: true),
                  ),
                _DetailRow(
                  icon: booking.isPaid
                      ? Icons.check_circle_outline
                      : Icons.payments_outlined,
                  label: isThai ? 'การชำระเงิน' : 'Payment',
                  value: booking.isPaid
                      ? (isThai ? 'ชำระแล้ว' : 'Paid')
                      : (isThai ? 'รอชำระเงิน' : 'Awaiting payment'),
                ),
                // #127: the "สถานะ / status" line carries a COLOURED status pill (not plain text)
                // so the current state stands out — especially `pending_completion` (the guard's
                // job awaiting the customer's confirmation), which otherwise read as a flat,
                // ignorable row. The pill's colour is status-driven (amber for the awaiting state,
                // green when completed, danger for terminals, blue/info while in flight).
                _StatusDetailRow(status: booking.status, isThai: isThai),
                // The cancellation reason reads as one more DETAIL PAIR, right under the status
                // pill it explains — same [_DetailRow] rhythm as address/hours/payment, so it is
                // information about the booking, not an error banner bolted onto the sheet.
                if (cancelReason.isNotEmpty) ...[
                  _DetailRow(
                    icon: Icons.info_outline,
                    label: isThai ? 'เหตุผล' : 'Reason',
                    value: cancelReason,
                  ),
                  if (cancelNote != null && cancelNote.isNotEmpty)
                    _DetailRow(
                      icon: Icons.notes_outlined,
                      label: isThai ? 'หมายเหตุ' : 'Note',
                      value: cancelNote,
                    ),
                ],
                // #129: the shared step timeline (accept → en route → arrived → working →
                // completed) INSIDE the details sheet, shown the instant a guard is assigned — the
                // SAME [BookingStatusTimeline] the main live + active-job screens render, so opening
                // "ดูรายละเอียด / Details" shows the work-status progress too. `started` is passed in
                // by the caller from the SAME source as the main timeline (the hour-1 check-in), so
                // the two never disagree during the guard's start→check-in window.
                if (booking.guardId != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
                    child: Divider(height: 1, color: PgTokens.colorBorder),
                  ),
                  Text(
                    isThai ? 'สถานะการทำงาน' : 'Job progress',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: PgTokens.space3),
                  BookingStatusTimeline(
                      status: booking.status, isThai: isThai, started: started),
                ],
                if (totalSatang != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
                    child: Divider(height: 1, color: PgTokens.colorBorder),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isThai ? 'ยอดรวม (ประมาณ)' : 'Total (estimate)',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        Money.format(totalSatang, decimals: true),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: PgTokens.colorGreen800,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// First 8 chars of an id (or the whole id if shorter) — a short human-quotable reference.
String _shortRef(String id) => id.length <= 8 ? id : id.substring(0, 8);

/// The booking-details sheet's "เจ้าหน้าที่ / Guard" row, resolving the assigned guard's REAL NAME
/// (#123) from the same IDOR-gated `/guards/{id}/public` read the live map + guard card use. Pure
/// enrichment: while it loads / if it degrades to null, it falls back to a short `#id` ref so the
/// customer always has a quotable reference (never a fabricated name).
class _GuardDetailRow extends ConsumerWidget {
  const _GuardDetailRow({required this.guardId, required this.isThai});

  final String guardId;
  final bool isThai;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref
        .watch(guardPublicProfileProvider(guardId))
        .valueOrNull
        ?.fullName
        ?.trim();
    return _DetailRow(
      icon: Icons.shield_outlined,
      label: isThai ? 'เจ้าหน้าที่' : 'Guard',
      value:
          (name != null && name.isNotEmpty) ? name : '#${_shortRef(guardId)}',
    );
  }
}

/// #127: the GUARD-facing "ลูกค้า / Customer" row, resolving the booking customer's REAL NAME from
/// the `/customers/{id}/public` read (the mirror of [_GuardDetailRow]; readable by any guard from
/// the job offer onwards — 2026-07-11 product decision). Pure enrichment: while it loads / if it
/// degrades to null (e.g. the customer set no name), it falls back to a short `#id` ref so the
/// guard always has a quotable reference (never a fabricated name).
class _CustomerDetailRow extends ConsumerWidget {
  const _CustomerDetailRow({required this.customerId, required this.isThai});

  final String customerId;
  final bool isThai;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref
        .watch(customerPublicProfileProvider(customerId))
        .valueOrNull
        ?.fullName
        ?.trim();
    return _DetailRow(
      icon: Icons.person_outline,
      label: isThai ? 'ลูกค้า' : 'Customer',
      value: (name != null && name.isNotEmpty)
          ? name
          : '#${_shortRef(customerId)}',
    );
  }
}

/// #127: the booking-details sheet's "สถานะ / Status" row, rendering the booking status as a
/// COLOURED PILL rather than a flat text value so the current state stands out. Same icon + bilingual
/// label gutter as a [_DetailRow], but the value is a [BookingStatusPill]. Shared by BOTH roles (the
/// guard now opens this same sheet), so the emphasised `pending_completion` state is obvious wherever
/// the sheet is opened.
class _StatusDetailRow extends StatelessWidget {
  const _StatusDetailRow({required this.status, required this.isThai});

  final BookingStatus status;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PgTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.flag_outlined,
              size: 18, color: PgTokens.colorTextMuted),
          const SizedBox(width: PgTokens.space3),
          Expanded(
            child: Text(isThai ? 'สถานะ' : 'Status',
                style: const TextStyle(
                    fontSize: 13, color: PgTokens.colorTextMuted)),
          ),
          const SizedBox(width: PgTokens.space3),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: BookingStatusPill(status: status, isThai: isThai),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PgTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: PgTokens.colorTextMuted),
          const SizedBox(width: PgTokens.space3),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: PgTokens.colorTextMuted)),
          ),
          const SizedBox(width: PgTokens.space3),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// READ-ONLY counterpart of [_PayNowBanner] for a NON-owner viewer (#87): a guard who reaches
/// the customer's live screen while the booking is accepted-but-unpaid must NEVER see the pay
/// button — only this passive "รอลูกค้าชำระเงิน / Awaiting customer payment" notice. Mirrors the
/// guard active-job screen's `_AwaitingPaymentNotice` (same warning tokens + copy) so the guard
/// sees a consistent message wherever they land.
class _AwaitingCustomerPaymentNotice extends ConsumerWidget {
  const _AwaitingCustomerPaymentNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorWarningBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty,
              size: 16, color: PgTokens.colorWarning),
          const SizedBox(width: PgTokens.space2),
          Expanded(
            child: Text(
              isThai ? 'รอลูกค้าชำระเงิน' : 'Awaiting customer payment',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: PgTokens.colorWarning),
            ),
          ),
        ],
      ),
    );
  }
}

/// A PAID booking that hit a NEGATIVE terminal (guard withdrew → declined, or cancelled): reassure
/// the customer their money is coming back. The backend queues a full refund on cancel/decline, but
/// no screen said so — apparent silent money limbo (deep-review). Owner-only, gated by the caller.
class _RefundComingBanner extends ConsumerWidget {
  const _RefundComingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorWarningBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 16, color: PgTokens.colorWarning),
          const SizedBox(width: PgTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isThai ? 'กำลังคืนเงินให้คุณ' : 'A refund is on its way',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: PgTokens.colorWarning),
                ),
                const SizedBox(height: 2),
                Text(
                  isThai
                      ? 'งานถูกยกเลิก — ระบบจะคืนเงินเต็มจำนวนภายใน 3–5 วันทำการ'
                      : 'The job was cancelled — a full refund will be returned within 3–5 business days',
                  style: const TextStyle(
                      fontSize: 11.5, color: PgTokens.colorTextMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// PRE-PAY CTA: shown on the live screen while the booking is accepted-but-unpaid. Routes to the
/// PaymentScreen where the customer pays the server-computed estimate ("ชำระเงินเพื่อให้เจ้าหน้าที่
/// เริ่มงาน" — pay so the guard can set off). Display-only; the amount is computed + charged by the
/// payment service (the client posts only the booking id). OWNER-ONLY — gated by the caller so a
/// guard never sees the pay button (#87).
class _PayNowBanner extends ConsumerWidget {
  const _PayNowBanner({required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorAmber50,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        border: Border.all(color: PgTokens.colorAmber200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined,
                  size: 18, color: PgTokens.colorAmber700),
              const SizedBox(width: PgTokens.space2),
              Expanded(
                child: Text(
                  isThai
                      ? 'เจ้าหน้าที่รับงานแล้ว — ชำระเงินเพื่อเริ่มงาน'
                      : 'Guard accepted — pay to get started',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: PgTokens.space3),
          PgPrimaryButton(
            label: isThai ? 'ชำระเงิน' : 'Pay now',
            color: PgTokens.colorAmber500,
            foreground: PgTokens.colorOnAmber,
            onPressed: () => context.push('/booking/$bookingId/pay'),
          ),
        ],
      ),
    );
  }
}

/// Inline live travel-map embedded in the customer live screen: the guard's LIVE position + the
/// destination + the REAL road route between them, in a ~220px [TravelMapPreview] card. Reuses the
/// SAME data + markers the full-screen customer map ([GuardMapScreen]) uses — it watches
/// [guardLocationControllerProvider], which re-pulls on each booking-status WS frame (no polling).
///
/// REAL ROUTING (matches the guard nav): the road geometry comes from the shared
/// [guardRouteProvider] (OSRM via [RoutingService]), keyed by the SNAPPED guard origin + the booking
/// destination — origin = the guard's LIVE position, dest = [GuardTrack.target]. `snapOrigin` quantises
/// the origin to a ~100 m grid so the route is fetched once per cell and CACHED, not re-fetched on
/// each guard GPS update; the full-screen [GuardMapScreen] shares that same cached route. The guard
/// pin still animates along the real road line as its position updates.
///
/// FALLBACK: when the route is null (OSRM down / no guard fix yet) [TravelMapPreview] degrades to the
/// honest straight [mover]→[target] segment — never blank/crash. Tap / fullscreen expands to
/// `/booking/{id}/map`. Loading / no-fix degrade to a calm placeholder.
class _InlineGuardMap extends ConsumerWidget {
  const _InlineGuardMap({required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final track =
        ref.watch(guardLocationControllerProvider(bookingId)).valueOrNull;
    final guard = track?.guard;
    final target = track?.target;
    // The REAL road route, shared (via the cache) with the full-screen map — origin = the guard's
    // live position, dest = the booking target. Snapped so it re-fetches only when the guard crosses
    // a ~100 m cell, not on every GPS tick. Null (loading / OSRM down) → the preview's straight
    // fallback.
    final route = (guard != null && target != null)
        ? ref
            .watch(guardRouteProvider(
              start: snapOrigin(guard.point),
              end: snapDest(target),
            ))
            .valueOrNull
        : null;
    return TravelMapPreview(
      mover: guard?.point,
      target: target,
      routePoints: route?.polyline,
      moverMarker: GuardMapGuardMarker(heading: guard?.heading),
      targetMarker: GuardMapReferenceMarker(
        isThai: isThai,
        isDestination: track?.targetIsDestination ?? true,
      ),
      onExpand: () => context.push('/booking/$bookingId/map'),
    );
  }
}
