import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/models/booking.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_stepper.dart';
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

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: const PGuardHeader(
        title: 'งานที่กำลังทำ',
        subtitle: 'Active job',
        showBack: true,
        live: true,
        background: PgTokens.colorGreen800,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(PgTokens.space6),
              child: Text(
                e is ApiException
                    ? e.message
                    : 'โหลดงานไม่สำเร็จ / Could not load this job',
                textAlign: TextAlign.center,
                style: const TextStyle(color: PgTokens.colorTextMuted),
              ),
            ),
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
      child: Row(
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

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
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
          const Text('เวลาที่เหลือ / Time remaining',
              style: TextStyle(fontSize: 12, color: PgTokens.colorTextMuted)),
          const SizedBox(height: 2),
          Text(_fmt(remaining),
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: PgTokens.space3),
          ClipRRect(
            borderRadius: BorderRadius.circular(PgTokens.radiusFull),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: PgTokens.colorSunken,
              valueColor:
                  const AlwaysStoppedAnimation(PgTokens.colorPrimary),
            ),
          ),
          const SizedBox(height: PgTokens.space3),
          Row(
            children: [
              const Icon(Icons.fact_check_outlined,
                  size: 16, color: PgTokens.colorTextMuted),
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
                  : 'เช็คอินรอบที่ $dueIndex / Check in now',
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

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(activeJobControllerProvider(bookingId).notifier);
    final yes = await _confirm(context, 'ปฏิเสธงาน / Withdraw?',
        'ถอนตัวจากงานนี้ — ย้อนกลับไม่ได้\nThis releases the job and cannot be undone.');
    if (yes != true) return;
    final ok = await notifier.withdraw();
    if (ok && context.mounted) context.go('/home/guard');
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
            PgGhostButton(
              label: 'ปฏิเสธงาน / Withdraw',
              onPressed: busy ? null : () => _withdraw(context, ref),
            ),
          ],
        ));
      case JobStage.arrived:
        return bar(PgPrimaryButton(
          label: 'ถึงจุดนัดแล้ว / Arrived',
          busy: busy,
          onPressed: busy ? null : () => ctrl.arrived(),
        ));
      case JobStage.start:
        return bar(PgPrimaryButton(
          label: 'เริ่มงาน / Start job',
          color: PgTokens.colorAccent,
          foreground: PgTokens.colorOnAmber,
          busy: busy,
          onPressed: busy ? null : () => ctrl.start(),
        ));
      case JobStage.working:
        return bar(PgPrimaryButton(
          label: 'จบงาน / Complete',
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
