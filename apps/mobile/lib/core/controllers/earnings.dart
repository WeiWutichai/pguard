// Pure earnings math for the guard "รายได้" tab — no Flutter/HTTP imports, 100% unit-testable
// (CLAUDE.md: money math lives in core/controllers, screens only render).

import '../models/booking.dart';
import '../models/money.dart';

/// One row of `GET /payments/earnings` — the settle-time truth for a COMPLETED booking of the
/// signed-in guard. Pure parse (tolerant of decimal STRINGS or numbers on the wire).
class GuardEarningsRow {
  const GuardEarningsRow({
    required this.bookingId,
    this.actualHours,
    this.commissionPercentHundredths,
  });

  final String bookingId;

  /// Clamped hours ACTUALLY worked, persisted at reconcile; `null` when unreconciled.
  final double? actualHours;

  /// The commission applied to this job, in HUNDREDTHS of a percent (1250 = 12.50%); `null` when
  /// the row carries none (pre-migration settle) → the booking's own snapshot is used instead.
  final int? commissionPercentHundredths;

  static GuardEarningsRow? tryParse(Map<String, dynamic> json) {
    final id = json['booking_id'] as String?;
    if (id == null) return null;
    final rawHours = json['actual_hours'];
    final rawPct = json['commission_percent'];
    return GuardEarningsRow(
      bookingId: id,
      actualHours: rawHours is String
          ? double.tryParse(rawHours)
          : (rawHours is num ? rawHours.toDouble() : null),
      // NUMERIC(5,2) → integer hundredths; a number on the wire is stringified first so the
      // 2dp parser stays the single rounding rule.
      commissionPercentHundredths:
          rawPct == null ? null : Money.percentHundredths(rawPct.toString()),
    );
  }
}

/// A guard's pay for a job (or a window of jobs), split the way a payout screen must show it:
/// what was EARNED, what was TAKEN, and what LANDS. A net figure with no visible deduction is
/// exactly the kind of silent smaller number that destroys trust in a payout screen.
class GuardPay {
  const GuardPay({required this.grossSatang, required this.commissionSatang});

  const GuardPay.zero()
      : grossSatang = 0,
        commissionSatang = 0;

  /// `base_fee × actual_hours` — one guard's share before the platform's cut.
  final int grossSatang;

  /// The platform's per-service commission: `gross × commission_percent / 100`.
  final int commissionSatang;

  /// What the guard is actually paid.
  int get netSatang => grossSatang - commissionSatang;

  /// Whether anything was deducted at all (a 0% service shows no deduction line).
  bool get hasCommission => commissionSatang != 0;

  GuardPay operator +(GuardPay other) => GuardPay(
        grossSatang: grossSatang + other.grossSatang,
        commissionSatang: commissionSatang + other.commissionSatang,
      );
}

/// Earnings derivations from the guard's assigned bookings (`GET /v1/bookings`).
///
/// HONESTY NOTE: v2 has no earnings/settlement endpoint — every figure here is a client-side
/// ESTIMATE derived from the guard's completed bookings, and the UI labels it
/// "ประมาณการ / Estimated". `base_fee` is the ฿/hour/GUARD rate, so one guard's share of a
/// job is `base_fee × hours` — `guard_count` multiplies the customer's bill, never this
/// guard's pay. Tips are EXCLUDED: the design's earnings rows equal base × hours exactly
/// (Guard_App.md Screen 6: ฿230/h × 8h = ฿1,840) and v2 defines no per-guard tip split.
///
/// COMMISSION (2026-08): the platform's per-service commission is deducted from the GUARD's pay
/// (the customer pays the same either way), so every earnings figure here is NET of it —
/// `base_fee × actual_hours × (1 − pct/100)`. The percent is the BOOKING's own snapshot
/// (`commission_percent`, frozen at creation so a catalog edit never rewrites a booked job),
/// overridden by the settle's value from `GET /payments/earnings` when present. Screens render
/// [GuardPay] so the gross and the deduction stay visible next to the net.
class GuardEarnings {
  const GuardEarnings._();

  /// The jobs that earn: completed bookings, in the server's newest-first order.
  static List<Booking> completedJobs(List<Booking> all) =>
      all.where((b) => b.status == BookingStatus.completed).toList();

  /// The participant feed (`GET /v1/bookings`) is `ORDER BY created_at DESC LIMIT 100`
  /// (`services/booking/src/repo/mod.rs` `list_bookings`). Once a guard has this many rows the
  /// server silently drops the oldest-CREATED ones — and since earnings window by `scheduled_at`,
  /// a dropped row can still belong in a window, so any total may under-report.
  static const int feedRowCap = 100;

  /// True when the feed is at the row cap, so older jobs may have been dropped and every windowed
  /// total is potentially incomplete. The UI surfaces a "ยอดอาจไม่ครบ / may be incomplete" caveat.
  static bool feedMayBeTruncated(List<Booking> all) => all.length >= feedRowCap;

  /// The hours a job PAYS for, in preference order:
  ///  1. the reconciled [actualHours] from `GET /payments/earnings` (the settle-time truth — the
  ///     clamped hours ACTUALLY worked, matching the customer's reconciled net);
  ///  2. the booking's own `actual_seconds / 3600` — the SAME server-computed figure, stamped onto
  ///     the booking at completion, so a guard sees their reconciled pay the INSTANT the job
  ///     completes (before the earnings settle row is fetched), with no later jump;
  ///  3. the booked hours — the estimate, for a job not yet reconciled with neither source.
  static double payableHours(Booking b, {Map<String, double>? actualHours}) {
    final settled = actualHours?[b.id];
    if (settled != null) return settled;
    final secs = b.actualSeconds;
    if (secs != null) return secs / 3600;
    return (b.hours ?? 0).toDouble();
  }

  /// The hours to PRINT next to a job's pay figure — the ACTUAL payable hours the ฿ was computed
  /// from (via [payableHours]), so the row's own arithmetic (`base × hours`) never disagrees with
  /// its amount. When those differ from the BOOKED hours (an early finish reconciled below the
  /// estimate), the booked figure is shown in parentheses so the guard understands the drop instead
  /// of computing `base × booked` and reporting missing pay. Pure + testable.
  ///
  /// e.g. reconciled 5.5h of an 8h booking → `5.5 ชม. (จอง 8)`; not-yet-reconciled 8h → `8 ชม.`.
  static String hoursLabel(Booking b,
      {Map<String, double>? actualHours, required bool isThai}) {
    final booked = b.hours ?? 0;
    final payable = payableHours(b, actualHours: actualHours);
    final unit = isThai ? 'ชม.' : 'hrs';
    final payableStr = _trimHours(payable);
    // Within a rounding epsilon of the booked estimate → just the plain figure (no annotation).
    if ((payable - booked).abs() < 0.005) return '$payableStr $unit';
    return isThai
        ? '$payableStr $unit (จอง $booked)'
        : '$payableStr $unit (booked $booked)';
  }

  /// Format hours dropping a trailing `.0` (8 not 8.0) but keeping a real fraction (5.5).
  static String _trimHours(double h) {
    if ((h - h.roundToDouble()).abs() < 0.005) return h.round().toString();
    return h.toStringAsFixed(1);
  }

  /// The commission applied to this job, in HUNDREDTHS of a percent. The settle's value
  /// ([commissionPercent], keyed by booking id, from `GET /payments/earnings`) wins when present;
  /// otherwise the booking's own creation-time snapshot; 0 for a pre-migration job with neither.
  static int commissionHundredths(Booking b,
          {Map<String, int>? commissionPercent}) =>
      commissionPercent?[b.id] ?? b.commissionPercentHundredths;

  /// One guard's pay for a job, split gross / commission / net.
  ///   gross      = base_fee × payable hours
  ///   commission = gross × commission_percent / 100     (the platform's per-service cut)
  ///   net        = gross − commission                   ← what the guard is paid
  static GuardPay jobPay(Booking b,
      {Map<String, double>? actualHours, Map<String, int>? commissionPercent}) {
    final hrs = payableHours(b, actualHours: actualHours);
    final gross = (Money.satangFromString(b.baseFee) * hrs).round();
    final pct = commissionHundredths(b, commissionPercent: commissionPercent);
    return GuardPay(
      grossSatang: gross,
      commissionSatang: Money.percentOf(gross, pct),
    );
  }

  /// One guard's NET pay for a job, in satang — `base_fee × hours × (1 − pct/100)`.
  ///
  /// THE default figure every guard-facing screen shows, so "รายได้" means the same number
  /// everywhere (home stats, work history, earnings). The gross and the deduction behind it are
  /// available via [jobPay] and are itemised on the earnings screen.
  static int jobEarningsSatang(Booking b,
          {Map<String, double>? actualHours,
          Map<String, int>? commissionPercent}) =>
      jobPay(b, actualHours: actualHours, commissionPercent: commissionPercent)
          .netSatang;

  /// Σ [jobPay] over the completed bookings in [all] (gross + commission + net).
  static GuardPay totalPay(List<Booking> all,
      {Map<String, double>? actualHours, Map<String, int>? commissionPercent}) {
    var sum = const GuardPay.zero();
    for (final b in completedJobs(all)) {
      sum = sum +
          jobPay(b,
              actualHours: actualHours, commissionPercent: commissionPercent);
    }
    return sum;
  }

  /// Σ NET pay over the completed bookings in [all].
  static int totalEarningsSatang(List<Booking> all,
          {Map<String, double>? actualHours,
          Map<String, int>? commissionPercent}) =>
      totalPay(all,
              actualHours: actualHours, commissionPercent: commissionPercent)
          .netSatang;

  /// Window length in CALENDAR days. Day = today, Week = last 7 days, Month = last 30 days.
  static int windowDays(EarningsWindow w) => switch (w) {
        EarningsWindow.day => 1,
        EarningsWindow.week => 7,
        EarningsWindow.month => 30,
      };

  /// Σ estimated pay for completed jobs whose scheduled LOCAL date falls in a calendar-day range:
  /// the `days` days ending `offsetDays` days before today (offset 0 = the current window; offset =
  /// days = the immediately-prior window, for growth). CALENDAR-day bucketing — the SAME rule as
  /// [dailySeries] — so a job scheduled for LATER TODAY that is already completed is still counted.
  /// (The old rolling `(now − len, now]` window used a `!isAfter(now)` future-TIME guard that wrongly
  /// dropped a job booked for, say, 14:00 today when the clock read 11:58 → "฿0 today" despite
  /// completed jobs sitting in the list below.) ACCURACY caveat re the 100-row feed cap is unchanged
  /// ([feedMayBeTruncated]); every figure is labelled "ประมาณการ / Estimated" (method: base × hours).
  static GuardPay _sumCalendarDays(List<Booking> all, DateTime now, int days,
      {int offsetDays = 0,
      Map<String, double>? actualHours,
      Map<String, int>? commissionPercent}) {
    final local = now.toLocal();
    final end = DateTime(local.year, local.month, local.day - offsetDays);
    final start = DateTime(end.year, end.month, end.day - (days - 1));
    var sum = const GuardPay.zero();
    for (final b in completedJobs(all)) {
      final w = b.scheduledAt?.toLocal();
      if (w == null) continue;
      final d = DateTime(w.year, w.month, w.day);
      if (!d.isBefore(start) && !d.isAfter(end)) {
        sum = sum +
            jobPay(b,
                actualHours: actualHours, commissionPercent: commissionPercent);
      }
    }
    return sum;
  }

  /// Gross / commission / net for the current window (today / last 7 / last 30 days) — the hero
  /// shows all three, so the windowed total never hides its deduction either.
  static GuardPay payInWindow(List<Booking> all, DateTime now, EarningsWindow w,
          {Map<String, double>? actualHours,
          Map<String, int>? commissionPercent}) =>
      _sumCalendarDays(all, now, windowDays(w),
          actualHours: actualHours, commissionPercent: commissionPercent);

  /// Σ NET pay for completed jobs in the current window (today / last 7 / last 30 days).
  static int sumInWindow(List<Booking> all, DateTime now, EarningsWindow w,
          {Map<String, double>? actualHours,
          Map<String, int>? commissionPercent}) =>
      payInWindow(all, now, w,
              actualHours: actualHours, commissionPercent: commissionPercent)
          .netSatang;

  /// The completed jobs that MAKE UP [sumInWindow] — same calendar-day rule, newest first.
  ///
  /// The "รายการล่าสุด" list used to be all-time regardless of the Day/Week/Month selector, so a
  /// guard on the Day tab saw ฿0 sitting above a list of paid jobs and reasonably concluded the
  /// total was broken. Now the rows are the total's own terms: they add up to the number above.
  static List<Booking> jobsInWindow(
      List<Booking> all, DateTime now, EarningsWindow w) {
    final local = now.toLocal();
    final end = DateTime(local.year, local.month, local.day);
    final start = DateTime(end.year, end.month, end.day - (windowDays(w) - 1));
    final rows = completedJobs(all).where((b) {
      final t = b.scheduledAt?.toLocal();
      if (t == null) return false;
      final d = DateTime(t.year, t.month, t.day);
      return !d.isBefore(start) && !d.isAfter(end);
    }).toList()
      ..sort((a, b) => (b.scheduledAt ?? DateTime(0))
          .compareTo(a.scheduledAt ?? DateTime(0)));
    return rows;
  }

  /// Growth fraction vs the immediately-prior window of the same length (e.g. +0.14 = +14%).
  /// Compares NET against NET (take-home vs take-home). `null` when the prior window had no
  /// earnings (no honest baseline to compare against).
  static double? growth(List<Booking> all, DateTime now, EarningsWindow w,
      {Map<String, double>? actualHours, Map<String, int>? commissionPercent}) {
    final days = windowDays(w);
    final current = _sumCalendarDays(all, now, days,
            actualHours: actualHours, commissionPercent: commissionPercent)
        .netSatang;
    final prior = _sumCalendarDays(all, now, days,
            offsetDays: days,
            actualHours: actualHours,
            commissionPercent: commissionPercent)
        .netSatang;
    if (prior == 0) return null;
    return (current - prior) / prior;
  }

  /// The LOCAL calendar dates for the [dailySeries] bars, OLDEST first (last == today). Built with
  /// `DateTime(y, m, d - i)` so it stays correct across month boundaries (and DST, for non-TH
  /// locales). [dailySeries] buckets against this exact list, so a bar's value and its weekday
  /// label can never disagree.
  static List<DateTime> seriesDates(DateTime now, {int days = 7}) {
    final local = now.toLocal();
    return [
      for (var i = days - 1; i >= 0; i--)
        DateTime(local.year, local.month, local.day - i),
    ];
  }

  /// Estimated NET pay (satang) per day for the last [days] days ending today, OLDEST first.
  /// Bucketed by the job's scheduled LOCAL date against [seriesDates] — drives the 7-day bar chart.
  /// Net, like every other figure on the screen, so the bars add up to the hero.
  static List<int> dailySeries(List<Booking> all, DateTime now,
      {int days = 7,
      Map<String, double>? actualHours,
      Map<String, int>? commissionPercent}) {
    final dates = seriesDates(now, days: days);
    final buckets = List<int>.filled(days, 0);
    for (final b in completedJobs(all)) {
      final when = b.scheduledAt?.toLocal();
      if (when == null) continue;
      for (var i = 0; i < dates.length; i++) {
        if (when.year == dates[i].year &&
            when.month == dates[i].month &&
            when.day == dates[i].day) {
          buckets[i] += jobEarningsSatang(b,
              actualHours: actualHours, commissionPercent: commissionPercent);
          break;
        }
      }
    }
    return buckets;
  }
}

/// Rolling earnings windows for the Day/Week/Month tab bar.
enum EarningsWindow { day, week, month }
