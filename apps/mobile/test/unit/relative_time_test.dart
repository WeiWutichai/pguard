import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/relative_time.dart';

void main() {
  final now = DateTime.utc(2026, 6, 6, 12, 0, 0);

  group('RelativeTime.th', () {
    test('buckets by elapsed time', () {
      expect(RelativeTime.th(now.subtract(const Duration(seconds: 30)), now: now),
          'เมื่อสักครู่');
      expect(RelativeTime.th(now.subtract(const Duration(minutes: 5)), now: now),
          '5 นาที');
      expect(RelativeTime.th(now.subtract(const Duration(hours: 3)), now: now),
          '3 ชม.');
      expect(RelativeTime.th(now.subtract(const Duration(days: 2)), now: now),
          '2 วัน');
      expect(RelativeTime.th(now.subtract(const Duration(days: 21)), now: now),
          '3 สัปดาห์');
    });
  });

  group('RelativeTime.en', () {
    test('compact english forms', () {
      expect(RelativeTime.en(now.subtract(const Duration(seconds: 5)), now: now),
          'just now');
      expect(RelativeTime.en(now.subtract(const Duration(minutes: 12)), now: now),
          '12m');
      expect(RelativeTime.en(now.subtract(const Duration(hours: 5)), now: now),
          '5h');
      expect(RelativeTime.en(now.subtract(const Duration(days: 3)), now: now),
          '3d');
    });
  });

  test('future / clock-skew is treated as just now', () {
    expect(RelativeTime.th(now.add(const Duration(minutes: 5)), now: now),
        'เมื่อสักครู่');
  });

  test('normalises across timezones (compares in UTC)', () {
    // A local-zoned timestamp 5 min before `now` should still read "5 นาที".
    final localFiveMinAgo =
        now.subtract(const Duration(minutes: 5)).toLocal();
    expect(RelativeTime.th(localFiveMinAgo, now: now), '5 นาที');
  });
}
