import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/money.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// Incoming-job detail: full info + accept/decline. accept (POST) → opens the active-job
/// screen; decline (PUT) → returns to the dashboard. Per `Mobile - Guard App.html` (detail).
class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final err =
        await ref.read(guardJobsControllerProvider.notifier).accept(bookingId);
    if (!context.mounted) return;
    if (err != null) {
      _snack(context, err);
    } else {
      context.go('/guard/active/$bookingId');
    }
  }

  // First-come-accept: skipping an unaccepted offer is a local dismiss, not a server call.
  void _dismiss(BuildContext context, WidgetRef ref) {
    ref.read(guardJobsControllerProvider.notifier).dismiss(bookingId);
    context.pop();
  }

  static void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(activeJobControllerProvider(bookingId));

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: isThai ? 'รายละเอียดงาน' : 'Job detail',
        subtitle: isThai ? 'ดูข้อมูลก่อนรับงาน' : 'Job detail',
        showBack: true,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title: isThai ? 'โหลดงานไม่สำเร็จ' : 'Could not load this job',
            message: e is ApiException ? e.message : null,
            onRetry: () =>
                ref.invalidate(activeJobControllerProvider(bookingId)),
          ),
          data: (state) => _Body(
            isThai: isThai,
            booking: state.booking,
            onAccept: () => _accept(context, ref),
            onDismiss: () => _dismiss(context, ref),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.isThai,
    required this.booking,
    required this.onAccept,
    required this.onDismiss,
  });

  final bool isThai;
  final Booking booking;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  /// Booking fee = base_fee × hours × guard_count (server-owned base_fee, in satang).
  int get _feeSatang => Money.total(
        baseFeeSatang: Money.satangFromString(booking.baseFee),
        hours: booking.hours ?? 0,
        guardCount: booking.guardCount ?? 1,
      );

  @override
  Widget build(BuildContext context) {
    final canAccept = booking.status == BookingStatus.requested;
    final hours = booking.hours;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(PgTokens.space4),
            children: [
              // Screen 3 hierarchy: place-name title + service-type/hours subtitle.
              Text(
                booking.address ?? 'งานรักษาความปลอดภัย',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                hours != null
                    ? 'รปภ. ประจำจุด · $hours ชั่วโมง'
                    : 'รปภ. ประจำจุด',
                style: const TextStyle(
                    fontSize: 13, color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space4),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: isThai ? 'สถานที่' : 'Location',
                value: booking.address ?? '—',
              ),
              const SizedBox(height: PgTokens.space3),
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: isThai ? 'เวลา' : 'Time',
                value: JobDetailTime.window(
                    booking.scheduledAt, hours, DateTime.now()),
                trailing: Text(
                  Money.format(_feeSatang),
                  // Design --font-mono for money figures (now bundled).
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'IBMPlexMono',
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              const SizedBox(height: PgTokens.space3),
              _InfoRow(
                icon: Icons.people_outline,
                label: isThai ? 'จำนวนเจ้าหน้าที่' : 'Guards',
                value: '${booking.guardCount ?? 1} คน',
              ),
              if (!canAccept) ...[
                const SizedBox(height: PgTokens.space4),
                Text(
                  'สถานะ: ${BookingLifecycle.labelTh(booking.status)}',
                  style: const TextStyle(color: PgTokens.colorTextMuted),
                ),
              ],
            ],
          ),
        ),
        if (canAccept)
          Container(
            padding: const EdgeInsets.all(PgTokens.space4),
            decoration: const BoxDecoration(
              color: PgTokens.colorSurface,
              border: Border(top: BorderSide(color: PgTokens.colorBorder)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: PgGhostButton(label: 'ข้าม', onPressed: onDismiss),
                  ),
                  const SizedBox(width: PgTokens.space2),
                  Expanded(
                    child: PgPrimaryButton(
                        label: isThai ? 'รับงานนี้' : 'Accept job',
                        onPressed: onAccept),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Pure formatter for the เวลา row value ("วันนี้ 14:00 – 22:00"). Static + widget-free so it
/// is unit-testable. (The design's fix sketch shares GuardJobCard._timeWindow, but
/// `widgets/job_card.dart` is outside this slice's ownership — re-implemented here.)
class JobDetailTime {
  const JobDetailTime._();

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "วันนี้ HH:MM – HH:MM" when [scheduledAt] falls on [now]'s local date, else
  /// "D/M HH:MM – HH:MM"; falls back to the bare hours ("8 ชม.") or "—" when unscheduled.
  static String window(DateTime? scheduledAt, int? hours, DateTime now) {
    final start = scheduledAt?.toLocal();
    if (start == null) return hours != null ? '$hours ชม.' : '—';
    final end = start.add(Duration(hours: hours ?? 0));
    final sameDay = start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
    final day = sameDay ? 'วันนี้' : '${start.day}/${start.month}';
    return '$day ${_two(start.hour)}:${_two(start.minute)} – '
        '${_two(end.hour)}:${_two(end.minute)}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.trailing});

  final IconData icon;
  final String label;
  final String value;

  /// Optional right-aligned widget (Screen 3 puts the mono w600 fee on the เวลา row).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: PgTokens.colorPrimary),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: PgTokens.colorTextMuted)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: PgTokens.space2),
          trailing!,
        ],
      ],
    );
  }
}
