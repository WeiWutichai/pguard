import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/controllers/chat_launcher.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_stepper.dart';
import '../call/widgets/call_entry_button.dart';
import '../chat/chat_routes.dart';
import '../chat/widgets/chat_entry_button.dart';
import 'widgets/check_in_sheet.dart';

/// The active-job working screen: drives the lifecycle transitions (en-route → arrived → start
/// → complete), shows a DISPLAY-only countdown (from the client-recorded start time, since the
/// API doesn't expose work_started_at), and prompts the hourly photo+GPS check-in. Status flows
/// to the customer over the existing WS — nothing is polled here. Per `Mobile Guard.html`.
class ActiveJobScreen extends ConsumerWidget {
  const ActiveJobScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeJobControllerProvider(bookingId));
    final state = async.valueOrNull;
    final booking = state?.booking;
    final stage = state == null ? null : stageOf(state);
    final header = _headerFor(stage);
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
                    enabled: BookingLifecycle.isActive(booking.status),
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
            title: 'โหลดงานไม่สำเร็จ / Could not load this job',
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
({String title, String subtitle, Color background}) _headerFor(JobStage? stage) {
  switch (stage) {
    case JobStage.enRoute:
    case JobStage.arrived:
      return (
        title: 'กำลังเดินทาง',
        subtitle: 'En route',
        background: PgTokens.colorInfo, // nearest token to design #1F5FC2
      );
    case JobStage.start:
      return (
        title: 'ถึงที่หมายแล้ว',
        subtitle: 'Arrived',
        background: PgTokens.colorGreen800,
      );
    case JobStage.working:
      return (
        title: 'งานกำลังดำเนินอยู่',
        subtitle: 'Working',
        background: PgTokens.colorGreen800,
      );
    case JobStage.awaiting:
      return (
        title: 'รอลูกค้าตรวจสอบ',
        subtitle: 'Awaiting customer',
        background: PgTokens.colorAmber700, // nearest token to design sand #C26A1E
      );
    case JobStage.done:
    case null:
      return (
        title: 'งานที่กำลังทำ',
        subtitle: 'Active job',
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

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address});

  final String? address;

  @override
  Widget build(BuildContext context) {
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
                    const Text('สถานที่ลูกค้า / Customer location',
                        style: TextStyle(
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

  @override
  void initState() {
    super.initState();
    // Display-only 1s tick to refresh the countdown + due state. NOT status polling.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Design G4 countdown reads H:MM:SS with no leading zero on the hours ("3:24:15").
  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _checkIn(int hour) async {
    final ok = await showCheckInSheet(
      context: context,
      ref: ref,
      bookingId: widget.bookingId,
      hourNumber: hour,
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งรายงานเช็คอินแล้ว / Check-in sent')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final clock = state.clock;
    final schedule = state.schedule;
    if (clock == null || schedule == null) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now().toUtc();
    final remaining = clock.remaining(now);
    final progress = clock.progress(now).clamp(0.0, 1.0);
    final dueNow = schedule.isDueNow(now, state.completedCheckIns);
    final dueIndex = schedule.dueIndex(now);
    final nextAt = schedule.nextDueAt(now)?.toLocal();
    final missed = schedule.missed(now, state.completedCheckIns);

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
          // Design `.sb-count`: big number first, side label with the booked total.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_fmt(remaining),
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: PgTokens.colorText,
                      letterSpacing: -0.3,
                      fontFeatures: [FontFeature.tabularFigures()])),
              // Design gap 14px → space3, nearest token.
              const SizedBox(width: PgTokens.space3),
              Expanded(
                child: Text(
                  'เหลือ · จาก ${clock.hours} ชม. / left · of ${clock.hours} h',
                  style: const TextStyle(
                      fontSize: 11.5, color: PgTokens.colorTextMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: PgTokens.space3),
          ClipRRect(
            // Design `.sb-bar`: 7px tall, 4px radius.
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: PgTokens.colorSunken,
              valueColor:
                  const AlwaysStoppedAnimation(PgTokens.colorPrimary),
            ),
          ),
          const SizedBox(height: PgTokens.space3),
          _SlotTracker(
            total: schedule.totalSlots,
            dueIndex: dueIndex,
            completed: state.completedCheckIns,
          ),
          const SizedBox(height: PgTokens.space3),
          Row(
            children: [
              const Icon(Icons.schedule,
                  size: 13, color: PgTokens.colorTextMuted),
              const SizedBox(width: PgTokens.space1),
              Expanded(
                child: Text(
                  'เช็คอินแล้ว ${state.completedCheckIns.length}/${schedule.totalSlots}'
                  '${missed.isNotEmpty ? ' · พลาด ${missed.length}' : ''}'
                  '${nextAt != null ? ' · ถัดไป ${_hm(nextAt)}' : ''}',
                  style: const TextStyle(
                      fontSize: 12.5, color: PgTokens.colorTextMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: PgTokens.space3),
          if (dueNow)
            PgPrimaryButton(
              label: dueIndex == 0
                  ? 'เช็คอินเริ่มงาน / Start check-in'
                  : 'เช็คอินชั่วโมงที่ $dueIndex / Hour $dueIndex check-in',
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

  static String _hm(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)} น.';
  }
}

/// Design `.sb-slots`: per-hour check-in segments — done → success green, the currently due
/// slot → amber, pending → sunken. Pure render of the existing [CheckInSchedule] state.
class _SlotTracker extends StatelessWidget {
  const _SlotTracker({
    required this.total,
    required this.dueIndex,
    required this.completed,
  });

  final int total;
  final int dueIndex;
  final Set<int> completed;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: completed.contains(i)
                    ? PgTokens.colorSuccess
                    : i == dueIndex
                        ? PgTokens.colorWarning // amber-500
                        : PgTokens.colorSunken,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CheckInIdle extends StatelessWidget {
  const _CheckInIdle();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorSuccessBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 16, color: PgTokens.colorSuccess),
          SizedBox(width: PgTokens.space2),
          Expanded(
            child: Text('เช็คอินรอบนี้เรียบร้อย / Up to date on check-ins',
                style:
                    TextStyle(fontSize: 12.5, color: PgTokens.colorSuccess)),
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
      BuildContext context, String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ยกเลิก')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ยืนยัน')),
        ],
      ),
    );
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    // Capture the notifier BEFORE the dialog await so we never touch `ref` post-await.
    final notifier = ref.read(activeJobControllerProvider(bookingId).notifier);
    final yes = await _confirm(context, 'จบงาน / Complete job?',
        'ส่งคำขอจบงานให้ลูกค้าตรวจสอบ — ย้อนกลับไม่ได้\nThis requests completion and cannot be undone.');
    if (yes == true) await notifier.complete();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        return bar(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PgPrimaryButton(
              label: 'เริ่มเดินทาง / Go en route',
              busy: busy,
              onPressed: busy ? null : () => ctrl.enRoute(),
            ),
            const SizedBox(height: PgTokens.space1),
            // Opens the full withdraw flow (warning banner + reason + admin notes) —
            // replaces the old bare AlertDialog confirm.
            PgGhostButton(
              label: 'ปฏิเสธงาน / Withdraw',
              onPressed: busy
                  ? null
                  : () => context.push('/guard/active/$bookingId/withdraw'),
            ),
          ],
        ));
      case JobStage.arrived:
        return bar(PgPrimaryButton(
          label: 'ถึงแล้ว / Arrived',
          busy: busy,
          onPressed: busy ? null : () => ctrl.arrived(),
        ));
      case JobStage.start:
        // Design G3: the start CTA pulses (`.sb-btn.amber.pulse`).
        return bar(_PulsingGlow(
          child: PgPrimaryButton(
            label: 'เริ่มงาน / Start job',
            color: PgTokens.colorAccent,
            foreground: PgTokens.colorOnAmber,
            busy: busy,
            onPressed: busy ? null : () => ctrl.start(),
          ),
        ));
      case JobStage.working:
        return bar(PgPrimaryButton(
          label: 'จบงาน / End',
          busy: busy,
          onPressed: busy ? null : () => _complete(context, ref),
        ));
      case JobStage.awaiting:
        return bar(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('รอลูกค้าตรวจสอบการจบงาน\nAwaiting customer review',
                textAlign: TextAlign.center,
                style: TextStyle(color: PgTokens.colorTextMuted)),
            const SizedBox(height: PgTokens.space2),
            // Design G5: the primary CTA for this state is chatting the customer.
            _ChatCustomerButton(booking: state.booking),
            PgGhostButton(
              label: 'ดูสถานะสด / View live status',
              onPressed: () => context.push('/booking/$bookingId/live'),
            ),
          ],
        ));
      case JobStage.done:
        return bar(PgGhostButton(
          label: 'ดูสถานะสด / View live status',
          onPressed: () => context.push('/booking/$bookingId/live'),
        ));
    }
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
          ParticipantInput(
              userId: booking.customerId, role: ChatRole.customer),
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
      messenger.showSnackBar(const SnackBar(
          content: Text('เปิดแชทไม่สำเร็จ / Could not open chat')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PgGhostButton(
      label: 'แชตหาลูกค้า / Chat customer',
      onPressed: _busy ? null : _open,
    );
  }
}
