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

  /// One guard's estimated pay for a job, in satang: `base_fee × hours`.
  static int jobEarningsSatang(Booking b) =>
      Money.satangFromString(b.baseFee) * (b.hours ?? 0);

  /// Σ [jobEarningsSatang] over the completed bookings in [all].
  static int totalEarningsSatang(List<Booking> all) {
    var sum = 0;
    for (final b in completedJobs(all)) {
      sum += jobEarningsSatang(b);
    }
    return sum;
  }

  /// Length of a rolling earnings window. Day = 24h, Week = 7d, Month = 30d.
  static Duration windowLength(EarningsWindow w) => switch (w) {
        EarningsWindow.day => const Duration(days: 1),
        EarningsWindow.week => const Duration(days: 7),
        EarningsWindow.month => const Duration(days: 30),
      };

  /// Σ estimated pay for completed jobs scheduled in the window `(now − len, now]`.
  /// ACCURACY: derived from `GET /v1/bookings`, which is `ORDER BY created_at DESC LIMIT 100`
  /// ([feedRowCap]). When the feed is BELOW the cap it holds every booking, so the windowed total
  /// is complete. When it is AT the cap the server has dropped the oldest-CREATED rows — and
  /// because we window by `scheduled_at`, a dropped row can still fall inside the window, so the
  /// total may under-report. [feedMayBeTruncated] detects that case and the UI shows a
  /// completeness caveat; every figure is also labelled "ประมาณการ / Estimated" (method: base × hours).
  static int sumInWindow(List<Booking> all, DateTime now, EarningsWindow w) {
    final from = now.subtract(windowLength(w));
    var sum = 0;
    for (final b in completedJobs(all)) {
      final when = b.scheduledAt;
      if (when != null && when.isAfter(from) && !when.isAfter(now)) {
        sum += jobEarningsSatang(b);
      }
    }
    return sum;
  }

  /// Growth fraction vs the immediately-prior window of the same length (e.g. +0.14 = +14%).
  /// `null` when the prior window had no earnings (no honest baseline to compare against).
  static double? growth(List<Booking> all, DateTime now, EarningsWindow w) {
    final len = windowLength(w);
    final current = sumInWindow(all, now, w);
    final priorEnd = now.subtract(len);
    final priorFrom = priorEnd.subtract(len);
    var prior = 0;
    for (final b in completedJobs(all)) {
      final when = b.scheduledAt;
      if (when != null && when.isAfter(priorFrom) && !when.isAfter(priorEnd)) {
        prior += jobEarningsSatang(b);
      }
    }
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
      {int days = 7}) {
    final dates = seriesDates(now, days: days);
    final buckets = List<int>.filled(days, 0);
    for (final b in completedJobs(all)) {
      final when = b.scheduledAt?.toLocal();
      if (when == null) continue;
      for (var i = 0; i < dates.length; i++) {
        if (when.year == dates[i].year &&
            when.month == dates[i].month &&
            when.day == dates[i].day) {
          buckets[i] += jobEarningsSatang(b);
          break;
        }
      }
    }
    return buckets;
  }
}

/// Rolling earnings windows for the Day/Week/Month tab bar.
enum EarningsWindow { day, week, month }
