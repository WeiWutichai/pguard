import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/models/booking.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets/job_card.dart';

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

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    final err =
        await ref.read(guardJobsControllerProvider.notifier).decline(bookingId);
    if (!context.mounted) return;
    if (err != null) {
      _snack(context, err);
    } else {
      context.pop();
    }
  }

  static void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeJobControllerProvider(bookingId));

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: const PGuardHeader(
        title: 'รายละเอียดงาน',
        subtitle: 'Job detail',
        showBack: true,
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
          data: (state) => _Body(
            booking: state.booking,
            onAccept: () => _accept(context, ref),
            onDecline: () => _decline(context, ref),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.booking,
    required this.onAccept,
    required this.onDecline,
  });

  final Booking booking;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final canAccept = booking.status == BookingStatus.requested;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(PgTokens.space4),
            children: [
              GuardJobCard(booking: booking),
              const SizedBox(height: PgTokens.space4),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'สถานที่ / Location',
                value: booking.address ?? '—',
              ),
              const SizedBox(height: PgTokens.space3),
              _InfoRow(
                icon: Icons.people_outline,
                label: 'จำนวนเจ้าหน้าที่ / Guards',
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
                    width: 110,
                    child: PgGhostButton(label: 'ปฏิเสธ', onPressed: onDecline),
                  ),
                  const SizedBox(width: PgTokens.space2),
                  Expanded(
                    child: PgPrimaryButton(
                        label: 'รับงานนี้ / Accept job', onPressed: onAccept),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

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
      ],
    );
  }
}
