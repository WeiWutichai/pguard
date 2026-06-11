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
}
