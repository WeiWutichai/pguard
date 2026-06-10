// Pure timing math for the guard active-job screen — countdown + hourly check-in scheduling.
// No Flutter, no timers, no IO → fully unit-testable. The screen applies a 1s DISPLAY timer to
// re-read these (the countdown display timer is allowed; it is NOT status polling).
//
// `work_started_at` is NOT exposed on the Booking API response (only stamped server-side for
// proration), so the client records its own `startedAt` the moment the guard taps "start" and
// drives the DISPLAY countdown from that. It is a display estimate, not the authoritative basis.

/// Countdown/elapsed math for a started job of [hours] booked hours.
class WorkClock {
  const WorkClock({required this.startedAt, required this.hours});

  final DateTime startedAt;
  final int hours;

  Duration get total => Duration(hours: hours);

  /// Time worked so far, clamped to [0, total].
  Duration elapsed(DateTime now) {
    final e = now.difference(startedAt);
    if (e.isNegative) return Duration.zero;
    return e > total ? total : e;
  }

  /// Time left until the booked end, clamped to [0, total].
  Duration remaining(DateTime now) => total - elapsed(now);

  /// 0.0 → 1.0 progress through the booked window.
  double progress(DateTime now) {
    if (total.inSeconds == 0) return 1;
    return elapsed(now).inSeconds / total.inSeconds;
  }

  /// Whether the booked window has fully elapsed.
  bool isTimeUp(DateTime now) => remaining(now) == Duration.zero;
}

/// Hourly check-in schedule for a started job. There are exactly [hours] slots, indexed
/// 0..[hours]-1: slot 0 is the start-of-work check-in, slot N is due after N elapsed hours.
/// Each slot maps 1:1 to a server `hour_number` (slot N → hour N+1, see
/// `ActiveJobController.submitCheckIn`), so EVERY check-in has a distinct server record — there
/// is no end-of-shift slot that would clamp onto the previous hour and get silently absorbed as
/// a 409 duplicate (the documented PR #29 trade-off, now closed).
class CheckInSchedule {
  const CheckInSchedule({required this.startedAt, required this.hours});

  final DateTime startedAt;
  final int hours;

  /// Total check-in slots over the shift — one per booked hour (start + each subsequent hour).
  int get totalSlots => hours;

  /// The highest slot index whose time has arrived by [now] (0 at start, +1 each elapsed hour,
  /// capped at the last slot [hours]-1).
  int dueIndex(DateTime now) {
    final elapsedHours = now.difference(startedAt).inMinutes ~/ 60;
    if (elapsedHours < 0) return 0;
    final lastSlot = hours > 0 ? hours - 1 : 0;
    return elapsedHours > lastSlot ? lastSlot : elapsedHours;
  }

  /// When the next not-yet-due slot opens, or null if the final slot ([hours]-1) is already due.
  DateTime? nextDueAt(DateTime now) {
    final next = dueIndex(now) + 1;
    if (next >= hours) return null;
    return startedAt.add(Duration(hours: next));
  }

  /// The current slot is "due now" if it hasn't been submitted yet.
  bool isDueNow(DateTime now, Set<int> completed) =>
      !completed.contains(dueIndex(now));

  /// Slots strictly before the current one that were never submitted — their hour boundary has
  /// passed, so they are MISSED (the current due slot is not missed until the next boundary).
  Set<int> missed(DateTime now, Set<int> completed) {
    final due = dueIndex(now);
    final result = <int>{};
    for (var i = 0; i < due; i++) {
      if (!completed.contains(i)) result.add(i);
    }
    return result;
  }
}
