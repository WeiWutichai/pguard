// Pure earnings math for the guard "รายได้" tab — no Flutter/HTTP imports, 100% unit-testable
// (CLAUDE.md: money math lives in core/controllers, screens only render).

import '../models/booking.dart';
import '../models/money.dart';

/// Earnings derivations from the guard's assigned bookings (`GET /v1/bookings`).
///
/// HONESTY NOTE: v2 has no earnings/settlement endpoint — every figure here is a client-side
/// ESTIMATE derived from the guard's completed bookings, and the UI labels it
/// "ประมาณการ / Estimated". `base_fee` is the ฿/hour/GUARD rate, so one guard's share of a
/// job is `base_fee × hours` — `guard_count` multiplies the customer's bill, never this
/// guard's pay. Tips are EXCLUDED: the design's earnings rows equal base × hours exactly
/// (Guard_App.md Screen 6: ฿230/h × 8h = ฿1,840) and v2 defines no per-guard tip split.
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

  /// One guard's pay for a job, in satang: `base_fee × hours`. When [actualHours] carries an entry
  /// for this booking (from `GET /payments/earnings` — the clamped hours ACTUALLY worked, persisted
  /// at reconcile), that is used INSTEAD of the booked hours, so a job that finished early pays for
  /// the hours worked — matching the customer's reconciled net — rather than the full booked
  /// estimate that overstated it. Falls back to booked hours when there is no reconciled entry.
  static int jobEarningsSatang(Booking b, {Map<String, double>? actualHours}) {
    final hrs = actualHours?[b.id] ?? (b.hours ?? 0).toDouble();
    return (Money.satangFromString(b.baseFee) * hrs).round();
  }

  /// Σ [jobEarningsSatang] over the completed bookings in [all].
  static int totalEarningsSatang(List<Booking> all,
      {Map<String, double>? actualHours}) {
    var sum = 0;
    for (final b in completedJobs(all)) {
      sum += jobEarningsSatang(b, actualHours: actualHours);
    }
    return sum;
  }

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
  static int _sumCalendarDays(List<Booking> all, DateTime now, int days,
      {int offsetDays = 0, Map<String, double>? actualHours}) {
    final local = now.toLocal();
    final end = DateTime(local.year, local.month, local.day - offsetDays);
    final start = DateTime(end.year, end.month, end.day - (days - 1));
    var sum = 0;
    for (final b in completedJobs(all)) {
      final w = b.scheduledAt?.toLocal();
      if (w == null) continue;
      final d = DateTime(w.year, w.month, w.day);
      if (!d.isBefore(start) && !d.isAfter(end)) {
        sum += jobEarningsSatang(b, actualHours: actualHours);
      }
    }
    return sum;
  }

  /// Σ pay for completed jobs in the current window (today / last 7 / last 30 days).
  static int sumInWindow(List<Booking> all, DateTime now, EarningsWindow w,
          {Map<String, double>? actualHours}) =>
      _sumCalendarDays(all, now, windowDays(w), actualHours: actualHours);

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
  /// `null` when the prior window had no earnings (no honest baseline to compare against).
  static double? growth(List<Booking> all, DateTime now, EarningsWindow w,
      {Map<String, double>? actualHours}) {
    final days = windowDays(w);
    final current = _sumCalendarDays(all, now, days, actualHours: actualHours);
    final prior = _sumCalendarDays(all, now, days,
        offsetDays: days, actualHours: actualHours);
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

  /// Estimated pay (satang) per day for the last [days] days ending today, OLDEST first.
  /// Bucketed by the job's scheduled LOCAL date against [seriesDates] — drives the 7-day bar chart.
  static List<int> dailySeries(List<Booking> all, DateTime now,
      {int days = 7, Map<String, double>? actualHours}) {
    final dates = seriesDates(now, days: days);
    final buckets = List<int>.filled(days, 0);
    for (final b in completedJobs(all)) {
      final when = b.scheduledAt?.toLocal();
      if (when == null) continue;
      for (var i = 0; i < dates.length; i++) {
        if (when.year == dates[i].year &&
            when.month == dates[i].month &&
            when.day == dates[i].day) {
          buckets[i] += jobEarningsSatang(b, actualHours: actualHours);
          break;
        }
      }
    }
    return buckets;
  }
}

/// Rolling earnings windows for the Day/Week/Month tab bar.
enum EarningsWindow { day, week, month }
