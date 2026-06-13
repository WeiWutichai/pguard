import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../media/photo_capture.dart';
import '../models/booking.dart';
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
    final data = await ref.read(pguardApiProvider).get('/bookings/$bookingId');
    return ActiveJobState(
        booking: Booking.fromJson(data as Map<String, dynamic>));
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
