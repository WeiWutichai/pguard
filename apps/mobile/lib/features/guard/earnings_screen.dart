import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/customer_home_controller.dart'
    show thaiShortDate;
import '../../core/controllers/earnings.dart';
import '../../core/controllers/guard_earnings_controller.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/money.dart';
import '../../core/network/api_error_l10n.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pg_segmented_tabs.dart';
import '../../widgets/pg_skeleton.dart';
import '../../widgets/pguard_header.dart';

/// Guard "รายได้" tab — estimated earnings derived from the guard's COMPLETED bookings
/// (`GET /v1/bookings`, guard = assigned jobs). UI per Guard_App.md Screen 6 "Earnings":
/// a Day/Week/Month segmented control, a windowed mono hero with a growth line, a bar chart, and
/// "รายการล่าสุด" per-job rows. Shares [guardJobsControllerProvider] with the guard dashboard
/// (same endpoint — one cache); pull-to-refresh re-pulls, no polling.
///
/// ONE WINDOW, THREE VIEWS: the hero, the bars and the rows are all scoped to the SELECTED tab, so
/// the bars add up to the number above them and the rows add up to it too. The design only ever
/// drew the Week state, and the chart shipped hard-wired to 7 days while the hero followed the tab
/// — on เดือน that put a 30-day hero above a 7-day chart (reported as "กราฟข้อมูลยังไม่ตรง"), and on
/// วัน it put a ฿0 hero above bars showing money. [GuardEarnings.seriesFor] now buckets per window
/// and the sum-equals-hero property is locked by unit test.
///
/// COMMISSION: the platform's per-service cut comes out of the GUARD's pay, so every figure on
/// this screen is NET of it — and the gross and the deduction are shown NEXT TO the net, on the
/// hero and on every row. A payout screen that quietly prints a smaller number than the guard
/// expects is how a payout screen loses its guard's trust; the arithmetic is on the page.
///
/// HONESTY NOTE: v2 has no earnings/settlement ledger — every figure is a client-side ESTIMATE
/// (`base_fee × hours × (1 − commission)` per completed job, tip + guard_count excluded) labelled
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
    // Actual worked hours per booking (GET /payments/earnings). Best-effort: while it loads / on
    // error, fall back to an empty map → jobEarningsSatang uses booked hours (previous behaviour).
    final actualHours =
        ref.watch(guardEarningsHoursProvider).valueOrNull ?? const {};
    // The commission actually applied at settle, same endpoint. Absent (still loading / older
    // settle) → the booking's own creation-time `commission_percent` snapshot is used instead, so
    // the deduction is never invisible just because this read hasn't landed.
    final commissionPercent =
        ref.watch(guardCommissionPercentProvider).valueOrNull ?? const {};

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'รายได้' : 'Earnings',
        subtitle: isThai ? 'รายได้โดยประมาณ' : 'Earnings',
        showBack: true,
      ),
      // Stale-while-revalidate (perf-review #1): show the LAST-KNOWN earnings via `valueOrNull` (this
      // provider is shared with the dashboard — arriving from there is an instant cache hit), a
      // tabs+hero+chart skeleton on a genuine first load, and the error state only with no data.
      body: SafeArea(
        child: Builder(builder: (context) {
          final all = async.valueOrNull;
          if (all == null) {
            if (async.hasError) {
              return PgErrorState(
                title:
                    isThai ? 'โหลดรายได้ไม่สำเร็จ' : 'Could not load earnings',
                // Localize the detail so an offline/5xx failure reads in Thai (the raw English
                // transport string was leaking into the Thai UI — deep-review).
                message: async.error is ApiException
                    ? localizeApiError(isThai, async.error as ApiException)
                    : null,
                onRetry: () =>
                    ref.read(guardJobsControllerProvider.notifier).refresh(),
              );
            }
            return _EarningsSkeleton(
              isThai: isThai,
              windowIndex: _window.index,
              onSelectWindow: (i) =>
                  setState(() => _window = EarningsWindow.values[i]),
            );
          }
          final now = widget.now ?? DateTime.now();
          // The empty state is about whether this guard has ANY finished work at all; the chart
          // and the rows are both the SELECTED window's own terms — see
          // [GuardEarnings.seriesFor] / [GuardEarnings.jobsInWindow].
          final completed = GuardEarnings.completedJobs(all);
          final inWindow = GuardEarnings.jobsInWindow(all, now, _window);
          final series = GuardEarnings.seriesFor(all, now, _window,
              actualHours: actualHours, commissionPercent: commissionPercent);
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
                  pay: GuardEarnings.payInWindow(all, now, _window,
                      actualHours: actualHours,
                      commissionPercent: commissionPercent),
                  growth: GuardEarnings.growth(all, now, _window,
                      actualHours: actualHours,
                      commissionPercent: commissionPercent),
                  mayBeIncomplete: GuardEarnings.feedMayBeTruncated(all),
                ),
                if (completed.isEmpty)
                  _EmptyEarnings(isThai: isThai)
                else ...[
                  // One bar is not a chart: on วัน the window IS a single day, and its breakdown is
                  // the per-job rows right below. Drawing a lone always-full-height bar there would
                  // say nothing while looking like data.
                  if (series.isChartable)
                    _EarningsChart(series: series, isThai: isThai),
                  // The list is scoped to the selected window, so the rows sum to the hero.
                  Padding(
                    // Design separates 'รายการล่าสุด' from the chart by ~28px above.
                    padding: const EdgeInsets.fromLTRB(
                        PgTokens.space5, 28, PgTokens.space5, PgTokens.space2),
                    child: Text(
                      isThai ? 'รายการในช่วงนี้' : 'In this period',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: PgTokens.colorTextStrong),
                    ),
                  ),
                  if (inWindow.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          PgTokens.space5, 0, PgTokens.space5, PgTokens.space4),
                      child: Text(
                        isThai
                            ? 'ยังไม่มีงานที่เสร็จในช่วงนี้'
                            : 'No completed jobs in this period',
                        style: const TextStyle(
                            fontSize: 13, color: PgTokens.colorTextMuted),
                      ),
                    ),
                  for (final b in inWindow)
                    _EarningsRow(
                      booking: b,
                      isThai: isThai,
                      actualHours: actualHours,
                      commissionPercent: commissionPercent,
                    ),
                ],
              ],
            ),
          );
        }),
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
    required this.pay,
    required this.growth,
    required this.mayBeIncomplete,
  });

  final bool isThai;
  final EarningsWindow window;

  /// Gross, commission and net for the window — the hero prints the NET big and the gross and the
  /// deduction that produced it right underneath.
  final GuardPay pay;
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
            Money.format(pay.netSatang),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              fontFamily: 'IBMPlexMono',
              fontFeatures: [FontFeature.tabularFigures()],
              color: PgTokens.colorTextStrong,
            ),
          ),
          // THE DEDUCTION, in the open: gross → commission → net, so the big number above is never
          // a smaller figure than the guard expected with no explanation attached.
          if (pay.hasCommission) ...[
            const SizedBox(height: PgTokens.space2),
            _HeroBreakdownLine(
              label: isThai ? 'รายได้ก่อนหัก' : 'Gross',
              satang: pay.grossSatang,
            ),
            const SizedBox(height: 2),
            _HeroBreakdownLine(
              label: isThai ? 'หักค่าคอมมิชชั่น' : 'Platform commission',
              satang: -pay.commissionSatang,
              color: PgTokens.colorDanger,
            ),
            const SizedBox(height: 2),
            _HeroBreakdownLine(
              label: isThai ? 'รับสุทธิ' : 'Net paid to you',
              satang: pay.netSatang,
              bold: true,
            ),
          ],
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
            pay.hasCommission
                ? (isThai
                    ? 'ประมาณการจากงานที่เสร็จสิ้น (฿ พื้นฐาน × ชม. หักค่าคอมมิชชั่น)'
                    : 'Estimated from completed jobs (base ฿ × hours, less commission)')
                : (isThai
                    ? 'ประมาณการจากงานที่เสร็จสิ้น (฿ พื้นฐาน × ชม.)'
                    : 'Estimated from completed jobs (base ฿ × hours)'),
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

/// One line of the hero's gross → deduction → net arithmetic. Mono, tabular figures, so the three
/// amounts line up as a sum a guard can check at a glance.
class _HeroBreakdownLine extends StatelessWidget {
  const _HeroBreakdownLine({
    required this.label,
    required this.satang,
    this.color,
    this.bold = false,
  });

  final String label;
  final int satang;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color ?? PgTokens.colorTextMuted,
            ),
          ),
        ),
        Text(
          Money.format(satang, decimals: true),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            fontFamily: 'IBMPlexMono',
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color ?? PgTokens.colorText,
          ),
        ),
      ],
    );
  }
}

/// Design `ebars`, generalised: the bars are the DECOMPOSITION of the hero above them, so they
/// always cover the selected window and nothing else ([GuardEarnings.seriesFor]).
///
/// สัปดาห์ = 7 daily bars with weekday labels (จ อ พ … / Mo Tu …), which is what the design drew.
/// เดือน = 5 six-day blocks labelled with the date each block STARTS on — 30 daily bars across a
/// phone is ~11px each, unreadable, and the design never drew a month state at all. วัน has a
/// single bucket, so the screen drops the chart entirely rather than draw one meaningless bar.
///
/// Three rendering rules the old 7-day chart got wrong, each of which on its own made a correct
/// series look like broken data:
///  · the busiest bucket's ฿ is PRINTED. Heights normalise to it, and with no scale a lone ฿1 job
///    drew exactly the same dramatic full-height bar as a ฿10,000 one.
///  · a TRUE zero draws no fill, only the faint track. The old 0.07 min-height stub made ฿0 and a
///    real ฿1 day pixel-identical.
///  · the amber "current" bar is the block containing today, and only when it EARNED something —
///    an empty today used to render as an unexplained orange stub next to green ones.
class _EarningsChart extends StatelessWidget {
  const _EarningsChart({required this.series, required this.isThai});

  final EarningsSeries series;
  final bool isThai;

  static const _thWeekday = ['', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
  static const _enWeekday = ['', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  /// A daily bar names its weekday; a multi-day block names the date it starts on (the caption
  /// above says how many days a block covers, so the date reads as a block, not a point).
  String _label(EarningsBucket b) => b.isSingleDay
      ? (isThai ? _thWeekday : _enWeekday)[b.start.weekday]
      : thaiShortDate(b.start, isThai: isThai);

  /// What a screen reader gets, which the visual bar cannot carry: the bucket's full date range
  /// and its actual amount.
  String _semantics(EarningsBucket b) {
    final when = b.isSingleDay
        ? thaiShortDate(b.start, isThai: isThai)
        : '${thaiShortDate(b.start, isThai: isThai)} – ${thaiShortDate(b.end, isThai: isThai)}';
    return '$when ${Money.format(b.netSatang)}';
  }

  @override
  Widget build(BuildContext context) {
    final maxVal = series.maxSatang;
    final lastIndex = series.buckets.length - 1;
    // Built up-front rather than inline in the Row: an `Expanded` has to be a DIRECT child of the
    // Flex, so it cannot be wrapped in a per-bar Builder.
    final bars = <Widget>[];
    for (var i = 0; i < series.buckets.length; i++) {
      final b = series.buckets[i];
      if (i > 0) bars.add(const SizedBox(width: PgTokens.space2));
      bars.add(Expanded(
        child: _Bar(
          // A true ฿0 is 0.0 (track only); anything non-zero keeps a visible floor so a
          // small-but-real amount never disappears next to a big one.
          fraction:
              b.netSatang == 0 ? 0.0 : math.max(b.netSatang / maxVal, 0.06),
          highlight: i == lastIndex && b.netSatang > 0,
          label: _label(b),
          semanticsLabel: _semantics(b),
        ),
      ));
    }
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(PgTokens.space5, 14, PgTokens.space5, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  series.bucketDays == 1
                      ? (isThai ? 'รายได้ต่อวัน' : 'Per day')
                      : (isThai
                          ? 'แท่งละ ${series.bucketDays} วัน (เริ่มวันที่ใต้แท่ง)'
                          : '${series.bucketDays} days per bar, from the date below'),
                  style: const TextStyle(
                      fontSize: 11.5, color: PgTokens.colorTextMuted),
                ),
              ),
              // THE SCALE. Bar heights are relative to this one number; printing it is the
              // difference between a chart and a decoration.
              if (!series.isEmpty)
                Text(
                  isThai
                      ? 'สูงสุด ${Money.format(maxVal)}'
                      : 'Peak ${Money.format(maxVal)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'IBMPlexMono',
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: PgTokens.colorTextMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: bars),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.highlight,
    required this.label,
    required this.semanticsLabel,
  });

  /// 0.0 … 1.0 of the bar area; exactly 0.0 means "earned nothing", not "too small to see".
  final double fraction;

  /// This bucket contains today AND earned something (design: today's bar is amber).
  final bool highlight;
  final String label;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Semantics(
            label: semanticsLabel,
            child: Stack(
              children: [
                // The faint track keeps an empty bucket a visible column, so dropping the old
                // min-height stub costs no legibility while making ฿0 honestly empty.
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: PgTokens.colorSunken,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(5)),
                    ),
                  ),
                ),
                if (fraction > 0)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: fraction.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: highlight
                              ? PgTokens.colorAmber400
                              : PgTokens.colorPrimary,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: const TextStyle(fontSize: 10, color: PgTokens.colorTextFaint),
        ),
      ],
    );
  }
}

/// One earnings row per the design: green-100 shield icon, place, "date · N ชม.", mono ฿.
/// The ฿ is the guard's NET for that job; when commission was deducted the row also spells out
/// `gross − commission` underneath, so a row can never disagree with the guard's own arithmetic.
class _EarningsRow extends StatelessWidget {
  const _EarningsRow({
    required this.booking,
    required this.isThai,
    this.actualHours,
    this.commissionPercent,
  });

  final Booking booking;
  final bool isThai;
  final Map<String, double>? actualHours;
  final Map<String, int>? commissionPercent;

  @override
  Widget build(BuildContext context) {
    final when = booking.scheduledAt;
    final meta = [
      if (when != null) thaiShortDate(when, isThai: isThai),
      // ACTUAL payable hours (annotated with the booked estimate when they differ) so the row's
      // hours never disagree with its own ฿ figure after a reconcile.
      GuardEarnings.hoursLabel(booking,
          actualHours: actualHours, isThai: isThai),
    ].join(' · ');
    final pay = GuardEarnings.jobPay(booking,
        actualHours: actualHours, commissionPercent: commissionPercent);

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.format(pay.netSatang),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'IBMPlexMono',
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: PgTokens.colorTextStrong,
                ),
              ),
              if (pay.hasCommission) ...[
                const SizedBox(height: 1),
                Text(
                  isThai
                      ? '${Money.format(pay.grossSatang)} − ${Money.format(pay.commissionSatang)} ค่าคอม'
                      : '${Money.format(pay.grossSatang)} − ${Money.format(pay.commissionSatang)} fee',
                  style: const TextStyle(
                      fontSize: 10.5, color: PgTokens.colorTextMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// First-load skeleton (perf-review #1): the real Day/Week/Month tabs (already interactive) over a
/// hero + chart placeholder, so the earnings screen shows its shape instead of a bare spinner.
class _EarningsSkeleton extends StatelessWidget {
  const _EarningsSkeleton({
    required this.isThai,
    required this.windowIndex,
    required this.onSelectWindow,
  });

  final bool isThai;
  final int windowIndex;
  final ValueChanged<int> onSelectWindow;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        PgSegmentedTabs(
          labels: isThai
              ? const ['วัน', 'สัปดาห์', 'เดือน']
              : const ['Day', 'Week', 'Month'],
          selected: windowIndex,
          onSelect: onSelectWindow,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PgSkeletonBox(width: 120, height: 13),
              SizedBox(height: PgTokens.space2),
              PgSkeletonBox(width: 190, height: 34),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: PgSkeletonCard(height: 110),
        ),
      ],
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
