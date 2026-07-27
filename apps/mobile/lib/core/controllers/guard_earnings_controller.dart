import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers.dart';

part 'guard_earnings_controller.g.dart';

/// Actual worked hours per COMPLETED booking for the signed-in guard, from `GET /payments/earnings`
/// (keyed `booking_id → actual_hours`). Powers `base_fee × actual_hours` on the earnings screen so a
/// guard's pay reflects the hours ACTUALLY worked — matching the customer's reconciled net — instead
/// of the full booked estimate that overstated it (the reported "รปภ ได้เต็ม แต่ลูกค้าโดนคืนเงิน"
/// mismatch). A booking absent from the map (unreconciled / even-match, `actual_hours` null) falls
/// back to booked hours in [GuardEarnings.jobEarningsSatang]. Best-effort: on failure the earnings
/// screen just uses booked hours (the previous behaviour), never an error.
@riverpod
Future<Map<String, double>> guardEarningsHours(
    GuardEarningsHoursRef ref) async {
  final data = await ref.read(pguardApiProvider).get('/payments/earnings');
  final rows = data is List ? data : const [];
  final out = <String, double>{};
  for (final r in rows.whereType<Map<String, dynamic>>()) {
    final id = r['booking_id'] as String?;
    if (id == null) continue;
    final raw = r['actual_hours'];
    final hrs = raw is String
        ? double.tryParse(raw)
        : (raw is num ? raw.toDouble() : null);
    if (hrs != null) out[id] = hrs;
  }
  return out;
}
