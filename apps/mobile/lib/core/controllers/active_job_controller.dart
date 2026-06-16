import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../media/photo_capture.dart';
import '../models/booking.dart';
import '../models/progress_report.dart';
import '../models/tracking.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'guard_clock.dart';
import 'locale_controller.dart';

part 'active_job_controller.g.dart';

const Object _unset = Object();

/// State for the active-job screen: the booking, the client-recorded start time (the API does
/// NOT expose `work_started_at`, so we stamp it when the guard taps "start" to drive the DISPLAY
/// countdown), and which hourly check-ins have been submitted.
class ActiveJobState {
  const ActiveJobState({
    required this.booking,
    this.startedAt,
    this.completedCheckIns = const {},
    this.busy = false,
    this.error,
  });

  final Booking booking;
  final DateTime? startedAt;
  final Set<int> completedCheckIns;
  final bool busy;
  final String? error;

  int get hours => booking.hours ?? 0;

  /// Display countdown clock — available once the guard has started the job this session.
  WorkClock? get clock =>
      startedAt == null ? null : WorkClock(startedAt: startedAt!, hours: hours);

  /// Hourly check-in schedule — available once started.
  CheckInSchedule? get schedule => startedAt == null
      ? null
      : CheckInSchedule(startedAt: startedAt!, hours: hours);

  ActiveJobState copyWith({
    Booking? booking,
    DateTime? startedAt,
    Set<int>? completedCheckIns,
    bool? busy,
    Object? error = _unset,
  }) =>
      ActiveJobState(
        booking: booking ?? this.booking,
        startedAt: startedAt ?? this.startedAt,
        completedCheckIns: completedCheckIns ?? this.completedCheckIns,
        busy: busy ?? this.busy,
        error: identical(error, _unset) ? this.error : error as String?,
      );
}

/// Drives the active job: the lifecycle transitions a guard performs, and hourly check-in
/// submission. All math (countdown, check-in scheduling) lives in pure helpers ([WorkClock],
/// [CheckInSchedule]); this controller only does network + state.
@riverpod
class ActiveJobController extends _$ActiveJobController {
  @override
  Future<ActiveJobState> build(String bookingId) async {
    final api = ref.read(pguardApiProvider);
    final data = await api.get('/bookings/$bookingId');
    final booking = Booking.fromJson(data as Map<String, dynamic>);

    // Hydrate work state from the server's check-in trail so the working panel SURVIVES an app
    // restart / re-entry mid-shift (both `startedAt` and `completedCheckIns` are otherwise
    // client-session-only — a cold build would re-show "Start" and an empty slot tracker even for
    // a job already in progress). Hour N's check-in opens N−1h after start, so:
    //   • completedCheckIns ← reported hours mapped to slots (slot = hour_number − 1)
    //   • startedAt ← earliest (createdAt − (hour_number − 1)h) anchor (mirrors
    //     HourlyProgress.workStartedAt — the same estimate the customer live screen uses)
    // Best-effort: a failed/empty read just yields the pre-start state (no regression), and the
    // 409 DUPLICATE_CHECK_IN absorb in CheckInService still guards an accidental re-submit.
    var completed = const <int>{};
    DateTime? startedAt;
    try {
      // limit=200 (the endpoint's max, > MAX_BOOKING_HOURS=168) so a long shift's later check-ins
      // aren't dropped by the default page size of 50.
      final raw = await api.get(
        '/bookings/$bookingId/progress-reports',
        query: {'limit': 200},
      );
      // The server guarantees hour_number ∈ 1..hours; drop any defaulted 0 from a partial payload
      // so it taints neither the slot set nor the start-anchor.
      final reports = (raw as List)
          .whereType<Map<String, dynamic>>()
          .map(ProgressReport.fromJson)
          .where((r) => r.hourNumber >= 1)
          .toList();
      completed = reports.map((r) => r.hourNumber - 1).toSet();
      for (final r in reports) {
        final anchored = r.createdAt.subtract(Duration(hours: r.hourNumber - 1));
        if (startedAt == null || anchored.isBefore(startedAt)) startedAt = anchored;
      }
    } catch (_) {
      // No trail yet (or a transient read failure) → pre-start state. A transient miss self-heals:
      // tapping Start again is idempotent server-side (start_job keeps the original work_started_at).
    }

    return ActiveJobState(
      booking: booking,
      startedAt: startedAt,
      completedCheckIns: completed,
    );
  }

  /// `PUT /v1/bookings/{id}/decline` — the assigned guard withdraws after accepting
  /// (accepted → declined). Valid pre-arrival; the screen returns to the dashboard on success.
  Future<bool> withdraw() => _transition('decline');

  /// `PUT /v1/bookings/{id}/en-route`.
  Future<bool> enRoute() => _transition('en-route');

  /// `PUT /v1/bookings/{id}/arrived`.
  Future<bool> arrived() => _transition('arrived');

  /// `PUT /v1/bookings/{id}/start` — stamps the (display-only) client start time.
  Future<bool> start() => _transition('start', markStart: true);

  /// `PUT /v1/bookings/{id}/complete` — requests completion (→ pending_completion). Live status
  /// then flows to the customer over the existing WS; nothing to poll.
  Future<bool> complete() => _transition('complete');

  Future<bool> _transition(String action, {bool markStart = false}) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    state = AsyncData(current.copyWith(busy: true, error: null));
    try {
      final data = await ref
          .read(pguardApiProvider)
          .put('/bookings/${current.booking.id}/$action');
      final booking = Booking.fromJson(data as Map<String, dynamic>);
      state = AsyncData(current.copyWith(
        booking: booking,
        busy: false,
        startedAt: markStart ? DateTime.now().toUtc() : null,
      ));
      return true;
    } on ApiException catch (e) {
      state = AsyncData(current.copyWith(busy: false, error: e.message));
      return false;
    } catch (_) {
      state = AsyncData(current.copyWith(busy: false, error: _genericError()));
      return false;
    }
  }

  /// Localized fallback message for an unexpected (non-[ApiException]) failure, in the
  /// user's current display language.
  String _genericError() => ref.read(localeControllerProvider) == AppLocale.th
      ? 'เกิดข้อผิดพลาด'
      : 'Something went wrong';

  /// Submit the check-in for schedule slot [slot] (photo + optional GPS/note) via
  /// [CheckInService]. On success the slot is marked done.
  ///
  /// Slot↔hour mapping: the UI's [CheckInSchedule] slots are 0-based (slot 0 = the
  /// start-of-work check-in; slot N is due after N elapsed hours), but the server's
  /// `hour_number` is 1-based (`1..hours`). The schedule now exposes exactly `hours` slots
  /// (0..hours-1), so `slot + 1` lands in `1..hours` with no collision — every slot maps to a
  /// distinct server hour (no end-of-shift slot to clamp). The `clamp` to `hours` below is kept
  /// purely DEFENSIVE and can no longer trip for a real slot index. [completedCheckIns] stays
  /// slot-indexed so the schedule UI (dueIndex/missed) is unchanged.
  Future<bool> submitCheckIn({
    required int slot,
    required CapturedPhoto photo,
    GpsSample? gps,
    String? note,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    final maxHour = current.hours < 1 ? 1 : current.hours;
    final serverHour = slot + 1 > maxHour
        ? maxHour
        : slot + 1; // defensive clamp (never trips)
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    state = AsyncData(current.copyWith(busy: true, error: null));
    try {
      await ref.read(checkInServiceProvider).submit(
            bookingId: current.booking.id,
            hourNumber: serverHour,
            photo: photo,
            isThai: isThai,
            gps: gps,
            note: note,
          );
      state = AsyncData(current.copyWith(
        busy: false,
        completedCheckIns: {...current.completedCheckIns, slot},
      ));
      return true;
    } on ApiException catch (e) {
      state = AsyncData(current.copyWith(busy: false, error: e.message));
      return false;
    } catch (_) {
      state = AsyncData(current.copyWith(busy: false, error: _genericError()));
      return false;
    }
  }
}
