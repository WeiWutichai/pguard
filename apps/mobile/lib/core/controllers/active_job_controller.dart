import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../media/photo_capture.dart';
import '../models/booking.dart';
import '../models/progress_report.dart';
import '../models/tracking.dart';
import '../network/api_error_l10n.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'guard_clock.dart';
import 'locale_controller.dart';

part 'active_job_controller.g.dart';

const Object _unset = Object();

/// Remembers the guard's client-recorded work-start time per booking for the app session.
///
/// `work_started_at` is NOT exposed on the Booking API (it is the server-internal proration
/// basis), so the active-job screen's countdown + check-in schedule run off a client stamp taken
/// when the guard taps "Start job". That stamp lives only in [ActiveJobState] — which is wiped
/// whenever the controller is invalidated (e.g. the `resumed` re-fetch after the camera backgrounds
/// the app during a check-in). Before the FIRST check-in lands there is no progress-report to
/// re-anchor from, so a naive rebuild loses the start, collapses the working panel, and re-prompts
/// "Start job" — making a just-submitted round look unregistered. This keep-alive holder lets
/// [ActiveJobController.build] restore the start across rebuilds so the working session is stable.
class WorkSessionStore {
  final Map<String, DateTime> _startedAt = {};
  final Set<String> _checkInInFlight = {};
  final Set<String> _autoCompleteSuppressed = {};

  /// The client-recorded start for [bookingId], or null if the guard hasn't started it this session.
  DateTime? startedAt(String bookingId) => _startedAt[bookingId];

  /// True while a check-in submit (camera → POST) is in progress for [bookingId]. The screen reads
  /// this to SUPPRESS the `resumed` re-fetch while the check-in camera round-trip is happening — a
  /// rebuild mid-submit would drop the controller into `loading`, making the in-flight
  /// `submitCheckIn` read a null state and silently no-op.
  bool isCheckInInFlight(String bookingId) =>
      _checkInInFlight.contains(bookingId);

  void beginCheckIn(String bookingId) => _checkInInFlight.add(bookingId);
  void endCheckIn(String bookingId) => _checkInInFlight.remove(bookingId);

  /// True once the CUSTOMER has REJECTED a completion for [bookingId] ("ให้ทำงานต่อ / keep
  /// working"). The customer is explicitly asking for work PAST the booked duration, so the
  /// booked-duration auto-complete must NOT re-fire — otherwise the reject-bounce remount of the
  /// working panel would instantly re-request completion (undoing the reject + re-spamming the
  /// "please review" push). Session-scoped: reset on app relaunch (a rare edge where a long-elapsed
  /// job could auto-complete once more — acceptable vs. the reject ping-pong).
  bool isAutoCompleteSuppressed(String bookingId) =>
      _autoCompleteSuppressed.contains(bookingId);

  /// Suppress the booked-duration auto-complete for [bookingId] after a completion reject.
  void suppressAutoComplete(String bookingId) =>
      _autoCompleteSuppressed.add(bookingId);

  /// Record the start the moment the guard taps "Start job" (idempotent-friendly: keep the
  /// EARLIEST stamp so a re-tap / rebuild never pushes the countdown later).
  void markStarted(String bookingId, DateTime at) {
    final existing = _startedAt[bookingId];
    if (existing == null || at.isBefore(existing)) _startedAt[bookingId] = at;
  }

  /// Reconcile with the server-derived anchor (earliest check-in anchor). Keeps the EARLIEST of the
  /// two so a hydrated start never drifts later than the real one.
  void reconcile(String bookingId, DateTime at) => markStarted(bookingId, at);
}

@Riverpod(keepAlive: true)
WorkSessionStore workSessionStore(WorkSessionStoreRef ref) =>
    WorkSessionStore();

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
        final anchored =
            r.createdAt.subtract(Duration(hours: r.hourNumber - 1));
        if (startedAt == null || anchored.isBefore(startedAt)) {
          startedAt = anchored;
        }
      }
    } catch (_) {
      // No trail yet (or a transient read failure) → pre-start state. A transient miss self-heals:
      // tapping Start again is idempotent server-side (start_job keeps the original work_started_at).
    }

    // Anchor precedence: the SERVER's `work_started_at` (now on the booking snapshot — the
    // authoritative proration basis, survives app restart/logout) → the check-in-derived estimate
    // → the client-session stamp in the keep-alive [WorkSessionStore] (covers the window between
    // tapping Start and the snapshot refresh on an old backend that doesn't send the field yet).
    // The store is still reconciled so an invalidation mid-check-in can't wipe the anchor.
    startedAt = booking.workStartedAt ?? startedAt;
    final store = ref.read(workSessionStoreProvider);
    if (startedAt != null) {
      store.reconcile(bookingId, startedAt);
    }
    startedAt ??= store.startedAt(bookingId);

    return ActiveJobState(
      booking: booking,
      startedAt: startedAt,
      completedCheckIns: completed,
    );
  }

  /// Fold an EXTERNALLY-observed TERMINAL transition into the active-job state — used when the
  /// live booking-status WebSocket pushes a terminal the guard didn't drive: chiefly the
  /// CUSTOMER cancelling while the guard sits on the active-job screen. The active-job
  /// controller has no WS of its own (it re-fetches only on resume), so without this a cancel
  /// wouldn't surface until the guard backgrounded + resumed. ONLY terminal frames are folded
  /// (the caller already filters to terminals): terminals are FINAL + idempotent, so there is
  /// no ordering hazard — a non-terminal fold could be rewound by an at-least-once redelivered
  /// EARLIER frame, so those are deliberately NOT folded here (a stale non-terminal like a lost
  /// en_route PUT is instead corrected by the 409-triggered snapshot re-pull in `_transition`).
  /// Once the state is ALREADY terminal it never changes again (a dead job stays dead), so a
  /// late frame of any kind is ignored. Clears stale `busy`/`error` so the screen lands cleanly.
  void applyExternalStatus(BookingStatus status) {
    final current = state.valueOrNull;
    if (current == null || current.booking.status == status) return;
    // Defence-in-depth: only terminals fold, and never over an already-terminal state.
    if (!BookingLifecycle.isTerminal(status) ||
        BookingLifecycle.isTerminal(current.booking.status)) {
      return;
    }
    state = AsyncData(current.copyWith(
      booking: current.booking.applyEvent(BookingStatusEvent(
        bookingId: current.booking.id,
        status: status,
        occurredAt: DateTime.now().toUtc(),
      )),
      busy: false,
      error: null,
    ));
  }

  /// The CUSTOMER REJECTED the guard's completion request (`pending_completion → arrived`, the
  /// "ให้ทำงานต่อ / keep working" bounce), observed on the booking-status WS. The active-job
  /// controller has no WS of its own, so the screen forwards this here. We do NOT fold the raw
  /// non-terminal `arrived` frame (an at-least-once redelivered EARLIER frame could rewind it —
  /// the same hazard [applyExternalStatus] guards against); instead we re-pull the authoritative
  /// snapshot. The reject NEVER resets `work_started_at` (booking repo `transition` leaves it
  /// untouched), and the guard's `completedCheckIns` already holds the start check-in, so the
  /// re-fetch lands the guard back in the WORKING stage with the countdown continuing from the
  /// original anchor. Self-gated to only act while the controller is still `pending_completion`,
  /// so a normal `en_route → arrived` frame or a duplicate is a no-op.
  Future<void> resumeFromRejectedCompletion() async {
    final current = state.valueOrNull;
    if (current == null ||
        current.booking.status != BookingStatus.pendingCompletion) {
      return;
    }
    // The customer asked the guard to KEEP WORKING — suppress the booked-duration auto-complete so
    // the working panel that re-mounts on this bounce can't instantly re-request completion (which
    // would undo the reject and re-fire the "please review" push). The guard ends manually now.
    ref.read(workSessionStoreProvider).suppressAutoComplete(bookingId);
    await _refreshBookingSnapshot();
  }

  /// `PUT /v1/bookings/{id}/en-route`.
  Future<bool> enRoute() => _transition('en-route');

  /// `PUT /v1/bookings/{id}/arrived` — now WITH the guard's GPS fix so the backend can enforce the
  /// 120 m ARRIVED geofence (the proximity gate moved here from start: a guard can no longer mark
  /// arrived while far away, then get stuck). Reuses the same fresh one-shot read as start; a missing
  /// fix still sends the bodiless PUT and the backend decides (409 GPS_REQUIRED on a pinned booking),
  /// so the policy lives in exactly one place.
  Future<bool> arrived() async {
    final gps = await _startFix();
    return _transition(
      'arrived',
      body: gps == null
          ? null
          : {
              'lat': gps.lat,
              'lng': gps.lng,
              if (gps.accuracy != null) 'accuracy_m': gps.accuracy,
            },
    );
  }

  /// `PUT /v1/bookings/{id}/start` — stamps the server work-start time and still sends the guard's
  /// GPS fix so the backend records WHERE the job was started (audit). Start no longer geofences —
  /// the proximity gate moved to `arrived` (120 m) — but the fix is cheap and useful as an audit
  /// trail. A missing fix still sends the bodiless PUT.
  Future<bool> start() async {
    final gps = await _startFix();
    return _transition(
      'start',
      markStart: true,
      body: gps == null
          ? null
          : {
              'lat': gps.lat,
              'lng': gps.lng,
              if (gps.accuracy != null) 'accuracy_m': gps.accuracy,
            },
    );
  }

  /// The guard's GPS fix for a geofence/audit PUT — a FRESH one-shot read at the moment of
  /// pressing arrived/start (freshest is what the 120 m arrived fence wants; the streaming lease's
  /// last sample can be up to the ~15 m movement gate stale). Guarded so an unavailable/denied
  /// location source degrades to `null` (a bodiless PUT — the backend then decides: 409
  /// GPS_REQUIRED on a pinned booking) rather than throwing.
  Future<GpsSample?> _startFix() async {
    try {
      return await ref.read(locationServiceProvider).currentSample();
    } catch (_) {
      return null;
    }
  }

  /// `PUT /v1/bookings/{id}/complete` — requests completion (→ pending_completion). Live status
  /// then flows to the customer over the existing WS; nothing to poll.
  Future<bool> complete() => _transition('complete');

  Future<bool> _transition(
    String action, {
    bool markStart = false,
    Map<String, dynamic>? body,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    state = AsyncData(current.copyWith(busy: true, error: null));
    try {
      final data = await ref
          .read(pguardApiProvider)
          .put('/bookings/${current.booking.id}/$action', data: body);
      final booking = Booking.fromJson(data as Map<String, dynamic>);
      DateTime? startedAt;
      if (markStart) {
        // Prefer the server's authoritative stamp off the PUT response; the client stamp is
        // only the fallback against an old backend that doesn't return `work_started_at` yet.
        startedAt = booking.workStartedAt ?? DateTime.now().toUtc();
        // Persist the start so it SURVIVES a controller rebuild (notably the `resumed`
        // re-fetch when the check-in camera backgrounds the app before the first report
        // exists to re-anchor from).
        ref.read(workSessionStoreProvider).markStarted(booking.id, startedAt);
      }
      // A completion request SUCCEEDED → the booking is now pending_completion, and the ONLY way
      // back to the working stage is a customer reject. Record the auto-complete suppression NOW,
      // not only when this same controller instance observes the reject: if the guard navigated away
      // (the awaiting-stage CTA leaves the screen and disposes this autoDispose controller) before
      // the reject landed, a later working-stage remount would otherwise re-fire /complete within ~1s
      // and silently undo the customer's "keep working" (deep-review HIGH). The guard ends manually
      // via จบงาน from here on.
      if (action == 'complete') {
        ref.read(workSessionStoreProvider).suppressAutoComplete(booking.id);
      }
      // Rebase on the LATEST state, not the pre-await `current` — a terminal (e.g. a customer
      // cancel) folded by the WS listener while this PUT was in flight must win over our
      // just-succeeded transition (a dead job stays dead).
      final latest = state.valueOrNull ?? current;
      if (BookingLifecycle.isTerminal(latest.booking.status)) return true;
      state = AsyncData(latest.copyWith(
        booking: booking,
        busy: false,
        startedAt: startedAt,
      ));
      return true;
    } on ApiException catch (e) {
      final latest = state.valueOrNull ?? current;
      // Don't clobber a terminal folded mid-flight with a stale error banner.
      if (!BookingLifecycle.isTerminal(latest.booking.status)) {
        state = AsyncData(latest.copyWith(busy: false, error: _localizeApi(e)));
      }
      // A 409 means OUR snapshot disagrees with the server (already transitioned, cancelled
      // during a WS gap, unpaid...). Re-pull the booking best-effort so the screen re-renders
      // the TRUE state instead of leaving a stale enabled button that 409s forever.
      if (e.statusCode == 409) {
        unawaited(_refreshBookingSnapshot());
      }
      return false;
    } catch (_) {
      final latest = state.valueOrNull ?? current;
      if (!BookingLifecycle.isTerminal(latest.booking.status)) {
        state = AsyncData(latest.copyWith(busy: false, error: _genericError()));
      }
      return false;
    }
  }

  /// Best-effort re-pull of the booking snapshot after a 409 — folds ONLY the booking (keeps
  /// startedAt/check-ins/error) so the screen catches up with the server's real state. Never
  /// rewinds a locally-terminal job: if a terminal (a customer cancel) already folded in, the
  /// re-pull is dropped rather than risk resurrecting it from a not-yet-consistent read.
  Future<void> _refreshBookingSnapshot() async {
    try {
      final current = state.valueOrNull;
      if (current != null &&
          BookingLifecycle.isTerminal(current.booking.status)) {
        return;
      }
      final data =
          await ref.read(pguardApiProvider).get('/bookings/$bookingId');
      final booking = Booking.fromJson(data as Map<String, dynamic>);
      final latest = state.valueOrNull;
      if (latest == null ||
          BookingLifecycle.isTerminal(latest.booking.status)) {
        return;
      }
      state = AsyncData(latest.copyWith(booking: booking));
    } catch (_) {
      // Best-effort only — the user can still recover via resume/re-entry.
    }
  }

  /// Map a transition [ApiException] to a message in the user's language. The server's
  /// transition errors are English (contract messages); the guard-facing screen must explain
  /// them in Thai, keyed on the machine-readable `code` (raw message only as a last resort).
  String _localizeApi(ApiException e) {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    switch (e.code) {
      case 'PAYMENT_REQUIRED':
        return isThai
            ? 'ลูกค้ายังไม่ได้ชำระเงิน — เริ่มเดินทางได้หลังชำระเงินแล้ว'
            : 'Waiting for the customer to pay before going en route';
      case 'GPS_REQUIRED':
        return isThai
            ? 'ต้องมีสัญญาณ GPS เพื่อเริ่มงาน — เปิดตำแหน่ง (Location) แล้วลองใหม่'
            : 'A GPS fix is required to start — turn on Location and retry';
      case 'CHECK_IN_REQUIRED':
        // Server-side backstop for "จบงาน before the start check-in" — the screen already gates the
        // End button behind the start check-in, so this only surfaces for an out-of-sync client.
        return isThai
            ? 'ต้องเช็คอินเริ่มงาน (แนบรูป) ก่อนจึงจะจบงานได้'
            : 'File the start check-in photo before ending the job';
      case 'NOT_AT_SITE':
        // The server message carries the measured distance ("You are {d} m from the job
        // site (max 50 m)") — pull the first number for the Thai copy, degrade gracefully.
        final d = RegExp(r'\d+').firstMatch(e.message)?.group(0);
        return isThai
            ? (d != null
                ? 'คุณอยู่ห่างจากจุดงานประมาณ $d ม. — ต้องอยู่ในระยะ 50 ม. จึงจะเริ่มงานได้'
                : 'คุณอยู่นอกพื้นที่งาน — ต้องอยู่ในระยะ 50 ม. จากจุดงานจึงจะเริ่มงานได้')
            : e.message;
      default:
        if (e.statusCode == 409) {
          return isThai
              ? 'สถานะงานเปลี่ยนไปแล้ว — อัปเดตข้อมูลล่าสุดให้แล้ว ลองอีกครั้ง'
              : 'The job state changed — refreshed to the latest, please retry';
        }
        return e.message;
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
      state = AsyncData(current.copyWith(
          busy: false,
          error: localizeApiError(
              ref.read(localeControllerProvider) == AppLocale.th, e)));
      return false;
    } catch (_) {
      state = AsyncData(current.copyWith(busy: false, error: _genericError()));
      return false;
    }
  }
}
