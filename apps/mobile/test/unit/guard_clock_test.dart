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
      expect(
          c.elapsed(start.subtract(const Duration(minutes: 5))), Duration.zero);
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

    test('totalSlots = hours (one per booked hour, 1:1 to server hour_number)',
        () {
      // PR-#29 trade-off closed: hours slots (0..hours-1) → hours 1..hours, no end-of-shift
      // slot that would clamp/collide. An 8-hour shift has 8 check-ins, not 9.
      expect(s.totalSlots, 8);
    });

    test(
        'dueIndex grows one per elapsed hour, capped at the last slot (hours-1)',
        () {
      expect(s.dueIndex(start), 0);
      expect(s.dueIndex(start.add(const Duration(minutes: 59))), 0);
      expect(s.dueIndex(start.add(const Duration(hours: 1, minutes: 5))), 1);
      expect(s.dueIndex(start.add(const Duration(hours: 3))), 3);
      expect(s.dueIndex(start.add(const Duration(hours: 99))),
          7); // capped at hours-1
    });

    test(
        'nextDueAt is the next boundary, null once the last slot (hours-1) is due',
        () {
      expect(s.nextDueAt(start), start.add(const Duration(hours: 1)));
      // slot 6 due at +6h → next is slot 7 at +7h.
      expect(s.nextDueAt(start.add(const Duration(hours: 6))),
          start.add(const Duration(hours: 7)));
      // slot 7 (the last) due at +7h → no next slot.
      expect(s.nextDueAt(start.add(const Duration(hours: 7))), isNull);
      expect(s.nextDueAt(start.add(const Duration(hours: 8))), isNull);
    });

    test('isDueNow reflects whether the current slot is submitted', () {
      expect(s.isDueNow(start, {}), isTrue); // slot 0 due at start
      expect(s.isDueNow(start, {0}), isFalse); // slot 0 already done
      final t = start.add(const Duration(hours: 2, minutes: 10));
      expect(s.isDueNow(t, {0, 1}), isTrue); // slot 2 due, not done
      expect(s.isDueNow(t, {0, 1, 2}), isFalse);
    });

    test('missed = earlier slots never submitted (current slot not yet missed)',
        () {
      final t = start.add(const Duration(hours: 3, minutes: 5)); // dueIndex 3
      // slots 0,1,2 should be done; 1 missing → missed {1}; slot 3 is "due now", not missed.
      expect(s.missed(t, {0, 2, 3}), {1});
      expect(s.missed(t, {0, 1, 2}), isEmpty);
      // at start nothing can be missed yet
      expect(s.missed(start, {}), isEmpty);
    });
  });

  group('CheckInSchedule — check-in window upper bound (G1)', () {
    final s = CheckInSchedule(startedAt: start, hours: 8);

    test('windowClosesAt = booked end + 30-min back-fill grace', () {
      // 14:00 + 8h + 30m = 22:30.
      expect(
          s.windowClosesAt, start.add(const Duration(hours: 8, minutes: 30)));
    });

    test(
        'isWindowClosed flips STRICTLY after end+grace (the boundary is still open)',
        () {
      // Still within the booked window.
      expect(s.isWindowClosed(start.add(const Duration(hours: 8))), isFalse);
      // Exactly at end+grace → still open (server rejects on `now > worked_end + grace`).
      expect(s.isWindowClosed(start.add(const Duration(hours: 8, minutes: 30))),
          isFalse);
      // One second past the grace → closed.
      expect(
          s.isWindowClosed(
              start.add(const Duration(hours: 8, minutes: 30, seconds: 1))),
          isTrue);
      expect(s.isWindowClosed(start.add(const Duration(hours: 9))), isTrue);
    });

    test('the final slot stops being "due now" once the window closes', () {
      const filedThrough6 = {
        0,
        1,
        2,
        3,
        4,
        5,
        6
      }; // only the last slot (7) unfiled
      // Within grace (+8h10m): the final slot is still legitimately due — allow the late back-fill.
      expect(
          s.isDueNow(
              start.add(const Duration(hours: 8, minutes: 10)), filedThrough6),
          isTrue);
      // Past grace (+9h): the final slot is no longer presented as due (a late file would 409
      // CHECK_IN_WINDOW_CLOSED server-side), so the client stops offering it.
      expect(s.isDueNow(start.add(const Duration(hours: 9)), filedThrough6),
          isFalse);
    });
  });
}
