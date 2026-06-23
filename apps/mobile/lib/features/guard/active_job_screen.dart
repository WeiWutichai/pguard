import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/controllers/chat_launcher.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/progress_reports_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/models/progress_report.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/progress_report_viewer.dart';
import '../../widgets/status_stepper.dart';
import '../../widgets/work_progress.dart';
import '../call/widgets/call_entry_button.dart';
import '../chat/chat_routes.dart';
import '../chat/widgets/chat_entry_button.dart';
import 'widgets/check_in_sheet.dart';

/// The active-job working screen: drives the lifecycle transitions (en-route → arrived → start
/// → complete), shows a DISPLAY-only countdown (from the client-recorded start time, since the
/// API doesn't expose work_started_at), and prompts the hourly photo+GPS check-in. Status flows
/// to the customer over the existing WS — nothing is polled here. Per `Mobile Guard.html`.
class ActiveJobScreen extends ConsumerStatefulWidget {
  const ActiveJobScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends ConsumerState<ActiveJobScreen>
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
    // Belt-and-suspenders for a MISSED payment push (foreground push handling can be skipped while
    // backgrounded): re-fetch the guard's active job on resume so a `paid_at` that landed while the
    // app was away un-gates "Go en route". This is a one-shot fetch on an event (resume), NOT a
    // Timer.periodic — the active-job controller has no live WS, so a manual re-pull is the only way
    // it reflects an async server change.
    if (lifecycle == AppLifecycleState.resumed) {
      ref.invalidate(activeJobControllerProvider(widget.bookingId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingId = widget.bookingId;
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(activeJobControllerProvider(bookingId));
    final state = async.valueOrNull;
    final booking = state?.booking;
    final stage = state == null ? null : stageOf(state);
    final header = _headerFor(stage, isThai);
    final myUserId = ref.watch(sessionProvider).user?.userId;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: header.title,
        subtitle: header.subtitle,
        showBack: true,
        // Design: only the G4 Working header carries the LIVE indicator.
        live: stage == JobStage.working,
        background: header.background,
        // Guard ↔ customer call + chat for this job.
        trailing: booking == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CallEntryButton(
                    bookingId: booking.id,
                    // Callable window matches the calling service (accepted/en_route/arrived);
                    // pendingCompletion is active but NOT callable → would 409.
                    enabled: BookingLifecycle.isCallable(booking.status),
                  ),
                  const SizedBox(width: PgTokens.space2),
                  ChatEntryButton(
                    requestId: booking.id,
                    requestStatus: booking.status.wire,
                    acting: ChatRole.guard,
                    myUserId: myUserId,
                    counterpartUserId: booking.customerId,
                  ),
                ],
              ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // Shared hi-fi error state (Mobile - System.html) — retry re-fetches the job.
          error: (e, _) => PgErrorState(
            title: isThai ? 'โหลดงานไม่สำเร็จ' : 'Could not load this job',
            message: e is ApiException ? e.message : null,
            onRetry: () =>
                ref.invalidate(activeJobControllerProvider(bookingId)),
          ),
          data: (state) => _Body(bookingId: bookingId, state: state),
        ),
      ),
    );
  }
}

/// The lifecycle stage a guard acts on next.
enum JobStage { enRoute, arrived, start, working, awaiting, done }

JobStage stageOf(ActiveJobState s) {
  switch (s.booking.status) {
    case BookingStatus.accepted:
      return JobStage.enRoute;
    case BookingStatus.enRoute:
      return JobStage.arrived;
    case BookingStatus.arrived:
      return s.startedAt == null ? JobStage.start : JobStage.working;
    case BookingStatus.pendingCompletion:
      return JobStage.awaiting;
    default:
      return JobStage.done;
  }
}

/// Header (title, subtitle, background) for the current lifecycle stage, per the design's
/// per-state guard headers: G2 En route (blue), G3 Arrived (green-800), G4 Working (green-800),
/// G5 Awaiting customer (sand → amber-700, nearest token). The journey phase (accepted +
/// travelling) maps to G2; the at-location-not-started stage maps to G3. Falls back to the
/// generic active-job header while loading / after completion.
({String title, String subtitle, Color background}) _headerFor(
    JobStage? stage, bool isThai) {
  switch (stage) {
    case JobStage.enRoute:
    case JobStage.arrived:
      return (
        title: isThai ? 'กำลังเดินทาง' : 'En route',
        subtitle: isThai ? 'กำลังไปหาลูกค้า' : 'On the way',
        background: PgTokens.colorInfo, // nearest token to design #1F5FC2
      );
    case JobStage.start:
      return (
        title: isThai ? 'ถึงที่หมายแล้ว' : 'Arrived',
        subtitle: isThai ? 'ถึงจุดหมายแล้ว' : 'At the location',
        background: PgTokens.colorGreen800,
      );
    case JobStage.working:
      return (
        title: isThai ? 'งานกำลังดำเนินอยู่' : 'Working',
        subtitle: isThai ? 'กำลังปฏิบัติงาน' : 'Job in progress',
        background: PgTokens.colorGreen800,
      );
    case JobStage.awaiting:
      return (
        title: isThai ? 'รอลูกค้าตรวจสอบ' : 'Awaiting customer',
        subtitle: isThai ? 'รอการตรวจสอบ' : 'Awaiting review',
        background:
            PgTokens.colorAmber700, // nearest token to design sand #C26A1E
      );
    case JobStage.done:
    case null:
      return (
        title: isThai ? 'งานที่กำลังทำ' : 'Active job',
        subtitle: isThai ? 'งานปัจจุบัน' : 'Current job',
        background: PgTokens.colorGreen800,
      );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.bookingId, required this.state});

  final String bookingId;
  final ActiveJobState state;

  @override
  Widget build(BuildContext context) {
    final booking = state.booking;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(PgTokens.space4),
            children: [
              _AddressCard(address: booking.address),
              const SizedBox(height: PgTokens.space4),
              Container(
                padding: const EdgeInsets.all(PgTokens.space4),
                decoration: BoxDecoration(
                  color: PgTokens.colorSurface,
                  borderRadius: BorderRadius.circular(PgTokens.radius2xl),
                  border: Border.all(color: PgTokens.colorBorder),
                ),
                child: BookingStatusStepper(status: booking.status),
              ),
              if (stageOf(state) == JobStage.working) ...[
                const SizedBox(height: PgTokens.space4),
                _WorkingPanel(bookingId: bookingId, state: state),
              ],
              if (state.error != null) ...[
                const SizedBox(height: PgTokens.space3),
                Text(state.error!,
                    style: const TextStyle(color: PgTokens.colorDanger)),
              ],
            ],
          ),
        ),
        _TransitionBar(bookingId: bookingId, state: state),
      ],
    );
  }
}

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.address});

  final String? address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    // The booking carries only a free-text address (no lat/lng in the v2 contract), so we show
    // the address over a stylised area band rather than a real customer pin.
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorGreen50,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorGreen100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined,
                  color: PgTokens.colorGreen800, size: 22),
              const SizedBox(width: PgTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isThai ? 'สถานที่ลูกค้า' : 'Customer location',
                        style: const TextStyle(
                            fontSize: 11, color: PgTokens.colorTextMuted)),
                    Text(address ?? '—',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: PgTokens.space3),
          const _MiniMapBand(),
        ],
      ),
    );
  }
}

/// Design `.sb-mini-map`: a decorative 50px map band with a teardrop location pin (no real map —
/// the v2 booking has no lat/lng, and no ETA badge for the same reason).
class _MiniMapBand extends StatelessWidget {
  const _MiniMapBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: PgTokens.colorSunken, // nearest token to design #E7ECE7
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Center(
        // Design `.gpin`: 18px teardrop — `border-radius: 50% 50% 50% 2px` rotated 45deg.
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: PgTokens.colorPrimary, // status-working green
              border: Border.all(color: PgTokens.colorSurface, width: 2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
                bottomRight: Radius.circular(9),
                bottomLeft: Radius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Working panel: a live display countdown + the hourly check-in status. Owns a 1s DISPLAY timer
/// (allowed — it is not status polling) that re-reads the pure [WorkClock]/[CheckInSchedule].
class _WorkingPanel extends ConsumerStatefulWidget {
  const _WorkingPanel({required this.bookingId, required this.state});

  final String bookingId;
  final ActiveJobState state;

  @override
  ConsumerState<_WorkingPanel> createState() => _WorkingPanelState();
}

class _WorkingPanelState extends ConsumerState<_WorkingPanel> {
  Timer? _ticker;

  /// Fired-once guard for the auto-complete: the 1s ticker re-evaluates "time up" every second,
  /// so without this it would re-PUT /complete repeatedly. Set the instant we kick off the auto
  /// completion (BEFORE the await) so a re-entrant tick can never double-fire it.
  bool _autoCompleted = false;

  @override
  void initState() {
    super.initState();
    // Display-only 1s tick to refresh the countdown + due state. NOT status polling.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _maybeAutoComplete();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Auto-close the job once the booked duration has fully ELAPSED while the guard app sits on
  /// the active-job screen — so the guard no longer has to remember to tap "จบงาน" at the end.
  /// Fires the SAME completion path the manual button uses (PUT /complete → pending_completion),
  /// exactly ONCE, and only while the job is still genuinely working (arrived + started, NOT
  /// already pending_completion/completed). The customer then approves via the existing flow.
  ///
  /// NOTE: this only fires while the guard app is open on THIS screen. A server-side scheduled
  /// auto-complete (for when the app is backgrounded/closed) is a backend follow-up — not built here.
  Future<void> _maybeAutoComplete() async {
    if (_autoCompleted) return;

    // Read the LIVE controller state (not the captured widget.state) so the status/busy checks
    // reflect any transition that landed since this panel was built.
    final live = ref.read(activeJobControllerProvider(widget.bookingId)).valueOrNull;
    if (live == null || live.busy) return;

    // Only auto-fire while still working: arrived + started, with the countdown known. The instant
    // the status advances (pending_completion/completed) this is no longer JobStage.working and we
    // must not fire (the guard may have closed early, or the customer already approved).
    if (live.booking.status != BookingStatus.arrived) return;
    final clock = live.clock;
    if (clock == null) return;
    if (!clock.isTimeUp(DateTime.now().toUtc())) return;

    // Claim the single shot BEFORE awaiting the network so re-entrant ticks bail at the top.
    _autoCompleted = true;
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final ok = await ref
        .read(activeJobControllerProvider(widget.bookingId).notifier)
        .complete();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isThai
              ? 'ครบเวลาทำงาน — ส่งจบงานให้ลูกค้าตรวจสอบ'
              : "Time's up — sent to the customer for review"),
        ),
      );
    } else {
      // The PUT failed (e.g. transient/409 because the status already advanced). Release the flag
      // so a later tick can retry; the controller already surfaced the error in state.error.
      _autoCompleted = false;
    }
  }

  /// The scheduled clock time of check-in slot [i] (startedAt + i hours), local "HH:MM".
  static String _slotTime(DateTime startedAt, int i) {
    final l = startedAt.add(Duration(hours: i)).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _checkIn(int hour) async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final ok = await showCheckInSheet(
      context: context,
      ref: ref,
      bookingId: widget.bookingId,
      hourNumber: hour,
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isThai ? 'ส่งรายงานเช็คอินแล้ว' : 'Check-in sent',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = widget.state;
    final clock = state.clock;
    final schedule = state.schedule;
    if (clock == null || schedule == null) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now().toUtc();
    final dueNow = schedule.isDueNow(now, state.completedCheckIns);
    final dueIndex = schedule.dueIndex(now);
    final startedAt = clock.startedAt; // clock != null ⟹ startedAt was set

    // The guard's own submitted reports (participants-only `GET …/progress-reports`, the same
    // source the customer live screen reads), keyed by the server's 1-based hour_number, so a
    // "Reported" row opens its photo + GPS + note. Slot i ↔ hour i+1. A failed/empty read just
    // leaves the rows non-tappable (no regression). Watched: re-pulls when status changes.
    final reportsByHour = <int, ProgressReport>{
      for (final r in ref
              .watch(progressReportsControllerProvider(widget.bookingId))
              .valueOrNull
              ?.reports ??
          const <ProgressReport>[])
        r.hourNumber: r,
    };

    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Design G4: the 74px ring countdown (shared widget) — shift window + elapsed + bar.
          WorkCountdownRing(clock: clock, isThai: isThai),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
            child: Divider(height: 1, color: PgTokens.colorBorder),
          ),
          // Design `.timeline` header: "ความคืบหน้า · 2 จาก 5 จุด".
          Text(
            isThai
                ? 'ความคืบหน้า · ${state.completedCheckIns.length} จาก ${schedule.totalSlots} จุด'
                : 'Progress · ${state.completedCheckIns.length} of ${schedule.totalSlots}',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorText),
          ),
          const SizedBox(height: PgTokens.space3),
          // Per-hour vertical timeline (shared widget). Slot i ↔ server hour i+1; the timestamp
          // is the scheduled due time (startedAt + i h) — per-report notes/photos are a follow-up.
          for (var i = 0; i < schedule.totalSlots; i++)
            CheckInTimelineRow(
              index: i + 1,
              title: i == 0
                  ? (isThai ? 'เริ่มงาน · เช็คอินจุดนัด' : 'Start · check in')
                  : (isThai ? 'ตรวจรอบที่ $i' : 'Round $i check-in'),
              done: state.completedCheckIns.contains(i),
              isCurrent: i == dueIndex && !state.completedCheckIns.contains(i),
              isLast: i == schedule.totalSlots - 1,
              time: _slotTime(startedAt, i),
              statusLabel: state.completedCheckIns.contains(i)
                  ? (isThai ? 'รายงานแล้ว' : 'Reported')
                  : i == dueIndex
                      ? (isThai ? 'ถึงกำหนด' : 'Due now')
                      : i < dueIndex
                          ? (isThai ? 'พลาด' : 'Missed')
                          : (isThai ? 'รอเช็คอิน' : 'Pending'),
              // Slot i is server hour i+1; a submitted report opens its photo+GPS+note.
              onTap: reportsByHour[i + 1] == null
                  ? null
                  : () => showProgressReportViewer(
                        context,
                        report: reportsByHour[i + 1]!,
                        isThai: isThai,
                      ),
            ),
          const SizedBox(height: PgTokens.space4),
          if (dueNow)
            PgPrimaryButton(
              label: dueIndex == 0
                  ? (isThai ? 'เช็คอินเริ่มงาน' : 'Start check-in')
                  : (isThai
                      ? 'เช็คอินชั่วโมงที่ $dueIndex'
                      : 'Hour $dueIndex check-in'),
              color: PgTokens.colorAccent,
              foreground: PgTokens.colorOnAmber,
              onPressed: () => _checkIn(dueIndex),
            )
          else
            const _CheckInIdle(),
        ],
      ),
    );
  }
}

class _CheckInIdle extends ConsumerWidget {
  const _CheckInIdle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Container(
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorSuccessBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 16, color: PgTokens.colorSuccess),
          const SizedBox(width: PgTokens.space2),
          Expanded(
            child: Text(
                isThai ? 'เช็คอินรอบนี้เรียบร้อย' : 'Up to date on check-ins',
                style: const TextStyle(
                    fontSize: 12.5, color: PgTokens.colorSuccess)),
          ),
        ],
      ),
    );
  }
}

class _TransitionBar extends ConsumerWidget {
  const _TransitionBar({required this.bookingId, required this.state});

  final String bookingId;
  final ActiveJobState state;

  Future<bool?> _confirm(
      BuildContext context, bool isThai, String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(isThai ? 'ยกเลิก' : 'Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(isThai ? 'ยืนยัน' : 'Confirm')),
        ],
      ),
    );
  }

  Future<void> _complete(
      BuildContext context, WidgetRef ref, bool isThai) async {
    // Capture the notifier BEFORE the dialog await so we never touch `ref` post-await.
    final notifier = ref.read(activeJobControllerProvider(bookingId).notifier);
    final yes = await _confirm(
      context,
      isThai,
      isThai ? 'จบงาน?' : 'Complete job?',
      isThai
          ? 'ส่งคำขอจบงานให้ลูกค้าตรวจสอบ — ย้อนกลับไม่ได้'
          : 'This requests completion and cannot be undone.',
    );
    if (yes == true) await notifier.complete();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final ctrl = ref.read(activeJobControllerProvider(bookingId).notifier);
    final stage = stageOf(state);
    final busy = state.busy;

    Widget bar(Widget child) => Container(
          padding: const EdgeInsets.all(PgTokens.space4),
          decoration: const BoxDecoration(
            color: PgTokens.colorSurface,
            border: Border(top: BorderSide(color: PgTokens.colorBorder)),
          ),
          child: SafeArea(top: false, child: child),
        );

    switch (stage) {
      case JobStage.enRoute:
        // PRE-PAY gate: `en_route` requires the customer to have PAID (booking.paid_at set, via
        // the payment.completed event). Until then the backend 409s the transition, so the CTA is
        // disabled and we show "รอลูกค้าชำระเงิน". paid_at arrives on the GET snapshot (the WS
        // frame carries only the status), so the screen re-pulls / re-enters reflect it.
        final paid = state.booking.isPaid;
        return bar(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!paid) ...[
              _AwaitingPaymentNotice(isThai: isThai),
              const SizedBox(height: PgTokens.space2),
            ],
            PgPrimaryButton(
              label: isThai ? 'เริ่มเดินทาง' : 'Go en route',
              busy: busy,
              onPressed: (busy || !paid) ? null : () => ctrl.enRoute(),
            ),
            const SizedBox(height: PgTokens.space1),
            // Opens the full withdraw flow (warning banner + reason + admin notes) —
            // replaces the old bare AlertDialog confirm.
            PgGhostButton(
              label: isThai ? 'ปฏิเสธงาน' : 'Withdraw',
              onPressed: busy
                  ? null
                  : () => context.push('/guard/active/$bookingId/withdraw'),
            ),
          ],
        ));
      case JobStage.arrived:
        // When the booking has site coordinates, route the guard through the full-screen
        // navigation map (which confirms arrival + starts work in one CTA). Older bookings
        // without coords keep the plain "Arrived" action.
        return bar(
          (state.booking.lat != null && state.booking.lng != null)
              ? PgPrimaryButton(
                  label: isThai ? 'นำทาง' : 'Navigate',
                  busy: busy,
                  onPressed: busy
                      ? null
                      : () => context.push('/guard/active/$bookingId/navigate'),
                )
              : PgPrimaryButton(
                  label: isThai ? 'ถึงแล้ว' : 'Arrived',
                  busy: busy,
                  onPressed: busy ? null : () => ctrl.arrived(),
                ),
        );
      case JobStage.start:
        // Design G3: the start CTA pulses (`.sb-btn.amber.pulse`).
        return bar(_PulsingGlow(
          child: PgPrimaryButton(
            label: isThai ? 'เริ่มงาน' : 'Start job',
            color: PgTokens.colorAccent,
            foreground: PgTokens.colorOnAmber,
            busy: busy,
            onPressed: busy ? null : () => ctrl.start(),
          ),
        ));
      case JobStage.working:
        return bar(PgPrimaryButton(
          label: isThai ? 'จบงาน' : 'End',
          busy: busy,
          onPressed: busy ? null : () => _complete(context, ref, isThai),
        ));
      case JobStage.awaiting:
        return bar(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                isThai ? 'รอลูกค้าตรวจสอบการจบงาน' : 'Awaiting customer review',
                textAlign: TextAlign.center,
                style: const TextStyle(color: PgTokens.colorTextMuted)),
            const SizedBox(height: PgTokens.space2),
            // Design G5: the primary CTA for this state is chatting the customer.
            _ChatCustomerButton(booking: state.booking),
            PgGhostButton(
              label: isThai ? 'ดูสถานะสด' : 'View live status',
              onPressed: () => context.push('/booking/$bookingId/live'),
            ),
          ],
        ));
      case JobStage.done:
        return bar(PgGhostButton(
          label: isThai ? 'ดูสถานะสด' : 'View live status',
          onPressed: () => context.push('/booking/$bookingId/live'),
        ));
    }
  }
}

/// The guard-side PRE-PAY gate notice shown above the disabled "Go en route" CTA while the
/// customer has not paid yet ("รอลูกค้าชำระเงิน" / "Awaiting customer payment").
class _AwaitingPaymentNotice extends StatelessWidget {
  const _AwaitingPaymentNotice({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
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

/// Design `@keyframes btnpulse`: a 1.8s repeating glow — a [PgTokens.colorAccent] shadow that
/// spreads 0→8px while fading 0.4→0 opacity. Display-only animation around the start CTA.
class _PulsingGlow extends StatefulWidget {
  const _PulsingGlow({required this.child});

  final Widget child;

  @override
  State<_PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<_PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radiusXl),
            boxShadow: [
              BoxShadow(
                color: PgTokens.colorAccent.withValues(alpha: 0.4 * (1 - t)),
                spreadRadius: 8 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Design G5's single CTA: chat the customer. Same find-or-create conversation flow as
/// [ChatEntryButton] (guarded by a busy flag — `POST /conversations` is not idempotent).
class _ChatCustomerButton extends ConsumerStatefulWidget {
  const _ChatCustomerButton({required this.booking});

  final Booking booking;

  @override
  ConsumerState<_ChatCustomerButton> createState() =>
      _ChatCustomerButtonState();
}

class _ChatCustomerButtonState extends ConsumerState<_ChatCustomerButton> {
  bool _busy = false;

  Future<void> _open() async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final booking = widget.booking;
    final myUserId = ref.read(sessionProvider).user?.userId;
    if (myUserId == null || _busy) return;

    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final launcher = ref.read(chatLauncherProvider);

    setState(() => _busy = true);
    try {
      final conversationId = await launcher.resolveConversationId(
        requestId: booking.id,
        acting: ChatRole.guard,
        requestStatus: booking.status.wire,
        participants: [
          ParticipantInput(userId: myUserId, role: ChatRole.guard),
          ParticipantInput(userId: booking.customerId, role: ChatRole.customer),
        ],
      );
      if (!mounted) return;
      await router.push(ChatRoutes.conversation(
        conversationId,
        acting: ChatRole.guard,
        readOnly: ChatReadOnly.fromStatus(booking.status.wire),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(isThai ? 'เปิดแชทไม่สำเร็จ' : 'Could not open chat')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return PgGhostButton(
      label: isThai ? 'แชตหาลูกค้า' : 'Chat customer',
      onPressed: _busy ? null : _open,
    );
  }
}
