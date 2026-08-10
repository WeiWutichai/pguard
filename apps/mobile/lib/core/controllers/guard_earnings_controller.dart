import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers.dart';
import 'earnings.dart';

part 'guard_earnings_controller.g.dart';

/// The signed-in guard's settle rows from `GET /payments/earnings`, keyed by `booking_id` — the
/// SETTLE-TIME truth behind every earnings figure: the hours actually worked and the commission
/// actually applied. ONE fetch; [guardEarningsHoursProvider] and
/// [guardCommissionPercentProvider] are projections of it, so the screens that want hours and the
/// screens that want the deduction never double-read the endpoint.
///
/// Best-effort by design: on failure the earnings screens fall back to the BOOKING's own snapshot
/// (booked hours + `commission_percent`), never an error state.
@riverpod
Future<Map<String, GuardEarningsRow>> guardEarningsRows(
    GuardEarningsRowsRef ref) async {
  final data = await ref.read(pguardApiProvider).get('/payments/earnings');
  final rows = data is List ? data : const [];
  final out = <String, GuardEarningsRow>{};
  for (final r in rows.whereType<Map<String, dynamic>>()) {
    final row = GuardEarningsRow.tryParse(r);
    if (row != null) out[row.bookingId] = row;
  }
  return out;
}

/// Actual worked hours per COMPLETED booking (`booking_id → actual_hours`). Powers
/// `base_fee × actual_hours` so a guard's pay reflects the hours ACTUALLY worked — matching the
/// customer's reconciled net — instead of the full booked estimate that overstated it (the
/// reported "รปภ ได้เต็ม แต่ลูกค้าโดนคืนเงิน" mismatch). A booking absent from the map
/// (unreconciled / even-match, `actual_hours` null) falls back to booked hours in
/// [GuardEarnings.jobEarningsSatang].
@riverpod
Future<Map<String, double>> guardEarningsHours(
    GuardEarningsHoursRef ref) async {
  final rows = await ref.watch(guardEarningsRowsProvider.future);
  return {
    for (final e in rows.entries)
      if (e.value.actualHours != null) e.key: e.value.actualHours!,
  };
}

/// Commission per COMPLETED booking in HUNDREDTHS of a percent (`booking_id → 1250` = 12.50%) —
/// what the platform actually deducted at settle. Overrides the booking's creation-time snapshot
/// in [GuardEarnings.commissionHundredths]; a booking absent here falls back to that snapshot, so
/// a pre-migration settle still shows the right deduction.
@riverpod
Future<Map<String, int>> guardCommissionPercent(
    GuardCommissionPercentRef ref) async {
  final rows = await ref.watch(guardEarningsRowsProvider.future);
  return {
    for (final e in rows.entries)
      if (e.value.commissionPercentHundredths != null)
        e.key: e.value.commissionPercentHundredths!,
  };
}
