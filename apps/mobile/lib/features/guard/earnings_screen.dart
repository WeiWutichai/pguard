import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/customer_home_controller.dart'
    show thaiShortDate;
import '../../core/controllers/earnings.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/money.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';

/// Guard "รายได้" tab — estimated earnings derived from the guard's COMPLETED bookings
/// (`GET /v1/bookings`, guard = assigned jobs). UI per Guard_App.md Screen 6 "Earnings":
/// mono hero number + "รายการล่าสุด" per-job rows (green shield icon, place, date · hours,
/// mono amount). Shares [guardJobsControllerProvider] with the guard dashboard (same
/// endpoint — one cache); pull-to-refresh re-pulls, no polling.
///
/// Design sections OMITTED (need data that does not exist in v2 — never invented):
///  - the Day/Week/Month tab bar, the 7-day bar chart, and the "↑ 14% จากสัปดาห์ก่อน"
///    growth line all need a time-series earnings ledger; v2 has no earnings endpoint and
///    `GET /v1/bookings` is a job list, not a guaranteed-complete ledger — windowed sums
///    derived from it could silently under-report. The hero therefore shows the honest
///    all-time total ("รวมรายได้") labelled "ประมาณการ / Estimated" instead of the mock's
///    "รายได้สัปดาห์นี้ / This week".
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(guardJobsControllerProvider);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: const PGuardHeader(
        title: 'รายได้',
        subtitle: 'Earnings',
        showBack: true,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title: 'โหลดรายได้ไม่สำเร็จ / Could not load earnings',
            message: e is ApiException ? e.message : null,
            onRetry: () =>
                ref.read(guardJobsControllerProvider.notifier).refresh(),
          ),
          data: (all) {
            final completed = GuardEarnings.completedJobs(all);
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(guardJobsControllerProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _EarningsHero(
                      totalSatang: GuardEarnings.totalEarningsSatang(all)),
                  if (completed.isEmpty)
                    const _EmptyEarnings()
                  else ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(PgTokens.space5,
                          PgTokens.space4, PgTokens.space5, PgTokens.space2),
                      child: Text(
                        'รายการล่าสุด / Recent',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: PgTokens.colorTextStrong),
                      ),
                    ),
                    for (final b in completed) _EarningsRow(booking: b),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Design `earn-hero`: padding 18×20, muted subtitle, 34px w600 mono big number — plus the
/// honesty line where the mock's growth indicator sits.
class _EarningsHero extends StatelessWidget {
  const _EarningsHero({required this.totalSatang});

  final int totalSatang;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'รวมรายได้ / Total earnings',
            style: TextStyle(fontSize: 12.5, color: PgTokens.colorTextMuted),
          ),
          const SizedBox(height: PgTokens.space1),
          Text(
            Money.format(totalSatang),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              fontFamily: 'IBMPlexMono',
              fontFeatures: [FontFeature.tabularFigures()],
              color: PgTokens.colorTextStrong,
            ),
          ),
          const SizedBox(height: PgTokens.space1),
          const Text(
            'ประมาณการ · ฿ พื้นฐาน × ชม. ต่องานที่เสร็จสิ้น\n'
            'Estimated · base ฿ × hours per completed job',
            style: TextStyle(fontSize: 12.5, color: PgTokens.colorTextMuted),
          ),
        ],
      ),
    );
  }
}

/// One earnings row per the design: green-100 shield icon, place, "date · N ชม.", mono ฿.
class _EarningsRow extends StatelessWidget {
  const _EarningsRow({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final when = booking.scheduledAt;
    final meta = [
      if (when != null) thaiShortDate(when),
      '${booking.hours ?? 0} ชม.',
    ].join(' · ');

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: PgTokens.space5, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PgTokens.colorBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: PgTokens.colorGreen100,
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            ),
            child: const Icon(Icons.shield_outlined,
                size: 18, color: PgTokens.colorGreen700),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.address ?? 'งานรักษาความปลอดภัย',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorTextStrong,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  meta,
                  style: const TextStyle(
                      fontSize: 11.5, color: PgTokens.colorTextMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: PgTokens.space2),
          Text(
            Money.format(GuardEarnings.jobEarningsSatang(booking)),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'IBMPlexMono',
              fontFeatures: [FontFeature.tabularFigures()],
              color: PgTokens.colorTextStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// No completed jobs yet (the spec has no designed empty state — house empty pattern).
class _EmptyEarnings extends StatelessWidget {
  const _EmptyEarnings();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 80),
        Icon(Icons.payments_outlined, size: 48, color: PgTokens.colorTextFaint),
        SizedBox(height: PgTokens.space3),
        Text(
          'ยังไม่มีรายได้\nNo earnings yet',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PgTokens.colorText),
        ),
        SizedBox(height: PgTokens.space2),
        Text(
          'รายได้จะแสดงเมื่องานเสร็จสิ้น\nEarnings appear when a job completes',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
        ),
      ],
    );
  }
}
