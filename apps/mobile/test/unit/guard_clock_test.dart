import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/guard_clock.dart';

void main() {
  final start = DateTime.utc(2026, 6, 5, 14); // 14:00

  group('WorkClock', () {
    final c = WorkClock(startedAt: start, hours: 8);

    test('elapsed/remaining clamp to [0, total]', () {
      expect(c.remaining(start), const Duration(hours: 8));
      expect(c.elapsed(start), Duration.zero);
      expect(c.remaining(start.add(const Duration(hours: 3))),
          const Duration(hours: 5));
      // before start → 0 elapsed, full remaining
      expect(c.elapsed(start.subtract(const Duration(minutes: 5))),
          Duration.zero);
      // past end → clamped
      expect(c.remaining(start.add(const Duration(hours: 9))), Duration.zero);
      expect(c.elapsed(start.add(const Duration(hours: 9))),
          const Duration(hours: 8));
    });

    test('progress and isTimeUp', () {
      expect(c.progress(start.add(const Duration(hours: 4))), 0.5);
      expect(c.isTimeUp(start.add(const Duration(hours: 8))), isTrue);
      expect(c.isTimeUp(start.add(const Duration(hours: 7))), isFalse);
    });

    test('total derives from hours', () {
      expect(c.total, const Duration(hours: 8));
    });
  });

  group('CheckInSchedule', () {
    final s = CheckInSchedule(startedAt: start, hours: 8);

    test('totalSlots = hours + 1 (start + one per hour)', () {
      expect(s.totalSlots, 9);
    });

    test('dueIndex grows one per elapsed hour, capped at hours', () {
      expect(s.dueIndex(start), 0);
      expect(s.dueIndex(start.add(const Duration(minutes: 59))), 0);
      expect(s.dueIndex(start.add(const Duration(hours: 1, minutes: 5))), 1);
      expect(s.dueIndex(start.add(const Duration(hours: 3))), 3);
      expect(s.dueIndex(start.add(const Duration(hours: 99))), 8); // capped
    });

    test('nextDueAt is the next boundary, null after the last slot', () {
      expect(s.nextDueAt(start), start.add(const Duration(hours: 1)));
      expect(s.nextDueAt(start.add(const Duration(hours: 8))), isNull);
    });

    test('isDueNow reflects whether the current slot is submitted', () {
      expect(s.isDueNow(start, {}), isTrue); // slot 0 due at start
      expect(s.isDueNow(start, {0}), isFalse); // slot 0 already done
      final t = start.add(const Duration(hours: 2, minutes: 10));
      expect(s.isDueNow(t, {0, 1}), isTrue); // slot 2 due, not done
      expect(s.isDueNow(t, {0, 1, 2}), isFalse);
    });

    test('missed = earlier slots never submitted (current slot not yet missed)', () {
      final t = start.add(const Duration(hours: 3, minutes: 5)); // dueIndex 3
      // slots 0,1,2 should be done; 1 missing → missed {1}; slot 3 is "due now", not missed.
      expect(s.missed(t, {0, 2, 3}), {1});
      expect(s.missed(t, {0, 1, 2}), isEmpty);
      // at start nothing can be missed yet
      expect(s.missed(start, {}), isEmpty);
    });
  });
}
