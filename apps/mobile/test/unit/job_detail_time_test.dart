import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/features/guard/job_detail_screen.dart';

void main() {
  final now = DateTime(2026, 6, 11, 9, 0);

  test('same-day window renders the design "วันนี้ 14:00 – 22:00" form', () {
    expect(
      JobDetailTime.window(DateTime(2026, 6, 11, 14, 0), 8, now),
      'วันนี้ 14:00 – 22:00',
    );
  });

  test('other-day window prefixes D/M instead of วันนี้', () {
    expect(
      JobDetailTime.window(DateTime(2026, 6, 15, 14, 0), 8, now),
      '15/6 14:00 – 22:00',
    );
  });

  test('unscheduled falls back to bare hours, then to a dash', () {
    expect(JobDetailTime.window(null, 8, now), '8 ชม.');
    expect(JobDetailTime.window(null, null, now), '—');
  });

  test('minutes are zero-padded and the end wraps past midnight cleanly', () {
    expect(
      JobDetailTime.window(DateTime(2026, 6, 11, 22, 5), 4, now),
      'วันนี้ 22:05 – 02:05',
    );
  });
}
