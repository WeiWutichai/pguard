import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/customer_home_controller.dart'
    show thaiShortDate;
import '../../core/controllers/earnings.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/money.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pg_segmented_tabs.dart';
import '../../widgets/pguard_header.dart';

/// Guard "รายได้" tab — estimated earnings derived from the guard's COMPLETED bookings
/// (`GET /v1/bookings`, guard = assigned jobs). UI per Guard_App.md Screen 6 "Earnings":
/// a Day/Week/Month segmented control, a windowed mono hero with a growth line, a 7-day
/// bar chart, and "รายการล่าสุด" per-job rows. Shares [guardJobsControllerProvider] with the
/// guard dashboard (same endpoint — one cache); pull-to-refresh re-pulls, no polling.
///
/// HONESTY NOTE: v2 has no earnings/settlement ledger — every figure is a client-side ESTIMATE
/// (`base_fee × hours` per completed job, tip + guard_count excluded) labelled
/// "ประมาณการ / Estimated". The figures come from `GET /v1/bookings`, which is
/// `ORDER BY created_at DESC LIMIT 100` ([GuardEarnings.feedRowCap]): below the cap the feed is
/// complete and the windowed totals are exact; AT the cap the server has dropped the oldest-created
/// rows, which can still belong in a window (we window by `scheduled_at`), so the screen shows a
/// "ยอดอาจไม่ครบ / total may be incomplete" caveat ([GuardEarnings.feedMayBeTruncated]) rather than
/// presenting a confident-but-possibly-low number. The growth line is omitted (not shown as 0%)
/// when the prior window had no earnings, so there is never a fabricated baseline. See
/// [GuardEarnings] for the math.
class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key, this.now});

  /// Test seam: pins "now" so windowed sums are deterministic. Production passes null →
  /// [DateTime.now] at build time.
  @visibleForTesting
  final DateTime? now;

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  EarningsWindow _window = EarningsWindow.week;

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(guardJobsControllerProvider);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'รายได้' : 'Earnings',
        subtitle: isThai ? 'รายได้โดยประมาณ' : 'Earnings',
        showBack: true,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title: isThai ? 'โหลดรายได้ไม่สำเร็จ' : 'Could not load earnings',
            message: e is ApiException ? e.message : null,
            onRetry: () =>
                ref.read(guardJobsControllerProvider.notifier).refresh(),
          ),
          data: (all) {
            final now = widget.now ?? DateTime.now();
            final completed = GuardEarnings.completedJobs(all);
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(guardJobsControllerProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  PgSegmentedTabs(
                    labels: isThai
                        ? const ['วัน', 'สัปดาห์', 'เดือน']
                        : const ['Day', 'Week', 'Month'],
                    selected: _window.index,
                    onSelect: (i) =>
                        setState(() => _window = EarningsWindow.values[i]),
                  ),
                  _EarningsHero(
                    isThai: isThai,
                    window: _window,
                    satang: GuardEarnings.sumInWindow(all, now, _window),
                    growth: GuardEarnings.growth(all, now, _window),
                    mayBeIncomplete: GuardEarnings.feedMayBeTruncated(all),
                  ),
                  if (completed.isEmpty)
                    _EmptyEarnings(isThai: isThai)
                  else ...[
                    _EarningsChart(
                      series: GuardEarnings.dailySeries(all, now),
                      dates: GuardEarnings.seriesDates(now),
                      isThai: isThai,
                    ),
                    // The "Recent" list is an all-time activity feed (newest-first), independent of
                    // the Day/Week/Month selector above — matching the mockup's flat "รายการล่าสุด".
                    Padding(
                      // Design separates 'รายการล่าสุด' from the chart by ~28px above.
                      padding: const EdgeInsets.fromLTRB(
                          PgTokens.space5, 28, PgTokens.space5, PgTokens.space2),
                      child: Text(
                        isThai ? 'รายการล่าสุด' : 'Recent',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: PgTokens.colorTextStrong),
                      ),
                    ),
                    for (final b in completed)
                      _EarningsRow(booking: b, isThai: isThai),
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

/// Design `earn-hero`: padding 18×20, muted window subtitle, 34px w600 mono big number, a
/// success/danger growth line (omitted when there is no prior-window baseline), and the honesty
/// caption where the mock has nothing — earnings here are an estimate.
class _EarningsHero extends StatelessWidget {
  const _EarningsHero({
    required this.isThai,
    required this.window,
    required this.satang,
    required this.growth,
    required this.mayBeIncomplete,
  });

  final bool isThai;
  final EarningsWindow window;
  final int satang;
  final double? growth;

  /// The feed hit the row cap, so older jobs may be missing — the total can under-report.
  final bool mayBeIncomplete;

  String get _subtitle => switch (window) {
        EarningsWindow.day => isThai ? 'รายได้วันนี้' : 'Today',
        EarningsWindow.week => isThai ? 'รายได้สัปดาห์นี้' : 'This week',
        EarningsWindow.month => isThai ? 'รายได้เดือนนี้' : 'This month',
      };

  String get _growthSuffix => switch (window) {
        EarningsWindow.day => isThai ? 'จากวันก่อน' : 'vs yesterday',
        EarningsWindow.week => isThai ? 'จากสัปดาห์ก่อน' : 'vs last week',
        EarningsWindow.month => isThai ? 'จากเดือนก่อน' : 'vs last month',
      };

  @override
  Widget build(BuildContext context) {
    final g = growth;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _subtitle,
            style:
                const TextStyle(fontSize: 12.5, color: PgTokens.colorTextMuted),
          ),
          const SizedBox(height: PgTokens.space1),
          Text(
            Money.format(satang),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              fontFamily: 'IBMPlexMono',
              fontFeatures: [FontFeature.tabularFigures()],
              color: PgTokens.colorTextStrong,
            ),
          ),
          if (g != null) ...[
            const SizedBox(height: PgTokens.space1),
            Text(
              '${g >= 0 ? '↑' : '↓'} ${(g.abs() * 100).round()}% $_growthSuffix',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: g >= 0 ? PgTokens.colorSuccess : PgTokens.colorDanger,
              ),
            ),
          ],
          const SizedBox(height: PgTokens.space1),
          Text(
            isThai
                ? 'ประมาณการจากงานที่เสร็จสิ้น (฿ พื้นฐาน × ชม.)'
                : 'Estimated from completed jobs (base ฿ × hours)',
            style:
                const TextStyle(fontSize: 11.5, color: PgTokens.colorTextMuted),
          ),
          if (mayBeIncomplete) ...[
            const SizedBox(height: PgTokens.space1),
            Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 13, color: PgTokens.colorWarning),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    isThai
                        ? 'แสดงเฉพาะงานล่าสุด · ยอดอาจไม่ครบ'
                        : 'Showing recent jobs only · total may be incomplete',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorWarning),
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

/// Design `ebars`: a 7-day daily bar chart (last 7 days ending today, oldest→newest). Bars are
/// brand-green; today's bar is amber. Heights normalise to the busiest day; an empty day still
/// shows the `min-height` stub. Weekday labels (จ อ พ … / Mo Tu …) come from each bar's real date.
class _EarningsChart extends StatelessWidget {
  const _EarningsChart({
    required this.series,
    required this.dates,
    required this.isThai,
  });

  /// Satang per day, oldest-first, length == number of bars; last entry is today.
  final List<int> series;

  /// The LOCAL calendar date for each bar (from `GuardEarnings.seriesDates`, same order as
  /// [series]) — the bar's weekday label is read from here so it can never drift from its value.
  final List<DateTime> dates;
  final bool isThai;

  static const _thWeekday = ['', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
  static const _enWeekday = ['', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  Widget build(BuildContext context) {
    final maxVal = series.fold<int>(0, math.max);
    final weekday = isThai ? _thWeekday : _enWeekday;
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(PgTokens.space5, 14, PgTokens.space5, 0),
      child: SizedBox(
        height: 110,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < series.length; i++) ...[
              if (i > 0) const SizedBox(width: PgTokens.space2),
              Expanded(
                child: _Bar(
                  // min-height stub (≈6px of the ~84px bar area) for empty days.
                  fraction:
                      maxVal == 0 ? 0.07 : math.max(series[i] / maxVal, 0.07),
                  isToday: i == series.length - 1,
                  label: weekday[dates[i].weekday],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(
      {required this.fraction, required this.isToday, required this.label});

  final double fraction;
  final bool isToday;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: fraction.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color:
                      isToday ? PgTokens.colorAmber400 : PgTokens.colorPrimary,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(5)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: PgTokens.colorTextFaint),
        ),
      ],
    );
  }
}

/// One earnings row per the design: green-100 shield icon, place, "date · N ชม.", mono ฿.
class _EarningsRow extends StatelessWidget {
  const _EarningsRow({required this.booking, required this.isThai});

  final Booking booking;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final when = booking.scheduledAt;
    final meta = [
      if (when != null) thaiShortDate(when, isThai: isThai),
      '${booking.hours ?? 0} ${isThai ? 'ชม.' : 'hrs'}',
    ].join(' · ');

    return Container(
      // Design `.prow` insets rows by 16px horizontally (align with the section header edge).
      padding:
          const EdgeInsets.symmetric(horizontal: PgTokens.space4, vertical: 14),
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
  const _EmptyEarnings({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.payments_outlined,
            size: 48, color: PgTokens.colorTextFaint),
        const SizedBox(height: PgTokens.space3),
        Text(
          isThai ? 'ยังไม่มีรายได้' : 'No earnings yet',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PgTokens.colorText),
        ),
        const SizedBox(height: PgTokens.space2),
        Text(
          isThai
              ? 'รายได้จะแสดงเมื่องานเสร็จสิ้น'
              : 'Earnings appear when a job completes',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
        ),
      ],
    );
  }
}
