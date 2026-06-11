import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/chat_format.dart';

// Local (non-UTC) instants so the local-calendar-day bucketing is deterministic
// regardless of the machine's timezone.
final now = DateTime(2026, 6, 11, 15, 30);

void main() {
  group('ChatFormat.listTime — design buckets (absolute, not relative)', () {
    test('same local day → clock time HH:mm', () {
      expect(
        ChatFormat.listTime(DateTime(2026, 6, 11, 14, 6), now: now, thai: true),
        '14:06',
      );
      expect(
        ChatFormat.listTime(DateTime(2026, 6, 11, 9, 5), now: now, thai: false),
        '09:05',
      );
    });

    test('previous local day → เมื่อวาน / Yesterday (even across midnight)', () {
      final lateYesterday = DateTime(2026, 6, 10, 23, 59);
      expect(ChatFormat.listTime(lateYesterday, now: now, thai: true), 'เมื่อวาน');
      expect(
          ChatFormat.listTime(lateYesterday, now: now, thai: false), 'Yesterday');
    });

    test('older → short Thai/EN date ("2 มิ.ย." / "2 Jun")', () {
      final older = DateTime(2026, 6, 2, 8, 0);
      expect(ChatFormat.listTime(older, now: now, thai: true), '2 มิ.ย.');
      expect(ChatFormat.listTime(older, now: now, thai: false), '2 Jun');
    });

    test('future/clock-skew clamps to the clock time, never a negative bucket', () {
      expect(
        ChatFormat.listTime(DateTime(2026, 6, 12, 0, 10), now: now, thai: true),
        '00:10',
      );
    });
  });

  group('ChatFormat.dayLabel — in-thread day separators', () {
    test('today → วันนี้ / Today', () {
      final when = DateTime(2026, 6, 11, 1, 0);
      expect(ChatFormat.dayLabel(when, now: now, thai: true), 'วันนี้');
      expect(ChatFormat.dayLabel(when, now: now, thai: false), 'Today');
    });

    test('yesterday → เมื่อวาน / Yesterday', () {
      final when = DateTime(2026, 6, 10, 21, 35);
      expect(ChatFormat.dayLabel(when, now: now, thai: true), 'เมื่อวาน');
      expect(ChatFormat.dayLabel(when, now: now, thai: false), 'Yesterday');
    });

    test('older → short date in each language', () {
      final when = DateTime(2026, 1, 31, 12, 0);
      expect(ChatFormat.dayLabel(when, now: now, thai: true), '31 ม.ค.');
      expect(ChatFormat.dayLabel(when, now: now, thai: false), '31 Jan');
    });
  });

  group('ChatFormat.sameLocalDay', () {
    test('same calendar day regardless of hour', () {
      expect(
        ChatFormat.sameLocalDay(
            DateTime(2026, 6, 11, 0, 1), DateTime(2026, 6, 11, 23, 59)),
        isTrue,
      );
    });

    test('one minute across midnight → different days', () {
      expect(
        ChatFormat.sameLocalDay(
            DateTime(2026, 6, 10, 23, 59), DateTime(2026, 6, 11, 0, 0)),
        isFalse,
      );
    });
  });

  group('ChatFormat.initials', () {
    test('two words → first letter of each, uppercased', () {
      expect(ChatFormat.initials('Somchai Prasert'), 'SP');
    });

    test('single word → first two characters', () {
      expect(ChatFormat.initials('Anan'), 'AN');
    });

    test('null/blank → ?', () {
      expect(ChatFormat.initials(null), '?');
      expect(ChatFormat.initials('   '), '?');
    });

    test('single character name', () {
      expect(ChatFormat.initials('ณ'), 'ณ');
    });
  });
}
