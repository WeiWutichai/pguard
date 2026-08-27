import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/tracking.dart';
import '../network/sockets/presence_socket.dart';
import '../providers.dart';
import 'guard_jobs_controller.dart';
import 'session_controller.dart';

part 'tracking_controller.g.dart';

/// Sentinel so [TrackingState.copyWith] can distinguish "leave lastSample unchanged" from
/// "clear it to null" (a null-coalescing copyWith cannot express the clear — the exact bug that
/// let a stale GPS fix survive an offline/online cycle and get re-broadcast as fresh).
const Object _unset = Object();

/// Guard presence state: whether the guard is online (visible to customers), whether GPS is
/// being streamed because of an ACTIVE JOB (independent of the manual online toggle), the live
/// connection link, and the latest GPS fix (for the accuracy readout).
class TrackingState {
  const TrackingState({
    this.online = false,
    this.jobIds = const {},
    this.link = PresenceLink.offline,
    this.lastSample,
  });

  /// The manual "พร้อมรับงาน" toggle (the guard is discoverable for new offers).
  final bool online;

  /// Booking ids currently holding a job-streaming lease (the guard has an active assigned job and
  /// is on its active-job/navigation screen). Non-empty ⟹ stream GPS even when [online] is false,
  /// so the customer sees the guard move in real time during the job.
  final Set<String> jobIds;

  final PresenceLink link;
  final GpsSample? lastSample;

  /// `true` whenever GPS should be flowing to presence: the manual toggle is on OR a job lease is
  /// held. The feed is open exactly when this is true.
  bool get streaming => online || jobIds.isNotEmpty;

  /// Qualitative accuracy band for the latest fix.
  GpsAccuracyBand get accuracyBand => GpsAccuracyBand.of(lastSample?.accuracy);

  /// Truly tracking = streaming, link up, AND at least one fix received.
  bool get isTracking =>
      streaming && link == PresenceLink.online && lastSample != null;

  /// [lastSample] uses the [_unset] sentinel so it can be CLEARED to null (pass `null` explicitly)
  /// as well as left unchanged (omit it) — a plain null-coalescing copyWith could only keep the old
  /// fix, so a teardown's `lastSample: null` was silently ignored and stale GPS survived.
  TrackingState copyWith({
    bool? online,
    Set<String>? jobIds,
    PresenceLink? link,
    Object? lastSample = _unset,
  }) =>
      TrackingState(
        online: online ?? this.online,
        jobIds: jobIds ?? this.jobIds,
        link: link ?? this.link,
        lastSample: identical(lastSample, _unset)
            ? this.lastSample
            : lastSample as GpsSample?,
      );
}

/// Drives the online/standby toggle: starts/stops GPS streaming over the presence WebSocket
/// (Bearer-on-upgrade). Subscribes to the GPS position STREAM (no `Timer.periodic`) and forwards
/// each fix to the presence feed. All transport lives behind injectable feeds so this is
/// unit-testable with fakes.
@Riverpod(keepAlive: true)
class TrackingController extends _$TrackingController {
  PresenceFeed? _feed;
  StreamSubscription<PresenceLink>? _linkSub;
  StreamSubscription<GpsSample>? _posSub;
  Timer? _keepalive;

  /// How often to re-send a current GPS fix while streaming. The presence service drops a guard
  /// from `online-guards` once its last fix is older than FRESHNESS_MINUTES=5; the movement-gated
  /// [LocationService.positionStream] emits nothing while the guard sits still waiting for a job,
  /// so without this a STATIONARY-but-online guard would go stale and undiscoverable. ~90 s stays
  /// well inside the 5-min window while keeping the GPS/battery cost low (a one-shot
  /// `getCurrentPosition`, not a continuous high-rate stream). This is the GPS UPLINK cadence — NOT
  /// the forbidden booking/assignment STATUS polling.
  static const Duration _keepaliveInterval = Duration(seconds: 90);

  /// The presence service drops a guard from `online-guards` once their last fix is older than
  /// FRESHNESS_MINUTES=5. When a fresh one-shot fix is unavailable (indoors / GPS-denied) the
  /// keepalive may fall back to the last cached sample — but ONLY if that cache is still inside this
  /// window. Re-broadcasting an hours-old fix (guard toggled offline, drove 20 km, came back online
  /// indoors) as the CURRENT position would advertise the guard as fresh at the wrong place.
  static const Duration _maxCachedFixAge = Duration(minutes: 5);

  @override
  TrackingState build() {
    ref.onDispose(_teardown);
    // Going offline must follow the guard out of the session — otherwise GPS keeps streaming
    // after logout (this provider is keepAlive and would survive the dashboard leaving). This also
    // drops any job-streaming lease.
    ref.listen(sessionProvider, (_, next) {
      if (next.status != SessionStatus.authenticated && state.streaming) {
        _shutDown();
      }
    });
    return const TrackingState();
  }

  Future<void> toggle() => state.online ? goOffline() : goOnline();

  /// Go online (manual "พร้อมรับงาน"): the guard becomes discoverable for new offers and starts
  /// streaming GPS. Opens the presence feed if it isn't already up (a job lease may already hold
  /// it open).
  Future<void> goOnline() async {
    if (state.online) return;
    state = state.copyWith(online: true);
    await _ensureStreaming();

    // Cheap safety net: refetch open jobs the moment the guard comes online, so any offer that
    // landed while they were offline (and whose push was therefore not delivered) shows up without
    // waiting for the next push or a manual pull-to-refresh. autoDispose-safe (see _onNewJob).
    ref.invalidate(guardJobsControllerProvider);
  }

  /// Go offline (standby): the guard is no longer discoverable. GPS keeps streaming if a job lease
  /// is still held (an active job must stay live to the customer regardless of this toggle).
  Future<void> goOffline() async {
    if (!state.online) return;
    state = state.copyWith(online: false);
    await _teardownIfIdle();
  }

  /// Take a job-streaming lease for [bookingId]: stream live GPS to presence for the duration of
  /// an ACTIVE JOB (accepted/en_route/arrived) regardless of the manual online toggle, so the
  /// customer's live map shows the guard moving. Idempotent per booking; the active-job /
  /// navigation screen takes the lease on enter and releases it on leave (or when the job ends).
  Future<void> startJobStreaming(String bookingId) async {
    if (state.jobIds.contains(bookingId)) return;
    state = state.copyWith(jobIds: {...state.jobIds, bookingId});
    await _ensureStreaming();
  }

  /// Release the job-streaming lease for [bookingId]. If nothing else is keeping the feed open
  /// (the manual toggle is off and no other job holds a lease), tear the feed/stream down.
  Future<void> stopJobStreaming(String bookingId) async {
    if (!state.jobIds.contains(bookingId)) return;
    state = state.copyWith(jobIds: {...state.jobIds}..remove(bookingId));
    await _teardownIfIdle();
  }

  /// Open the presence feed (if not already open) and start forwarding GPS fixes. Shared by the
  /// manual toggle and the job lease — the feed + position subscription are reference-counted by
  /// [TrackingState.streaming], so it is safe to call on every entry path. Idempotent.
  Future<void> _ensureStreaming() async {
    // Already streaming (the toggle or another job lease holds the feed open).
    if (_feed != null) return;

    // Request location permission on EVERY streaming-start path — the card toggle, the duty FAB,
    // AND the active-job lease land here. Without it the OS allow dialog never shows, the position
    // stream is empty, and the GPS line spins forever. Idempotent: when already granted
    // permission_handler returns immediately with no second dialog.
    await ref.read(permissionGateProvider).requestLocation();
    // A teardown may have raced in during the permission await; bail if streaming is no longer
    // wanted (or the feed was opened by a concurrent call).
    if (_feed != null || !state.streaming) return;
    final api = ref.read(pguardApiProvider);
    final feed = ref.read(presenceFeedBuilderProvider)(api.validAccessToken);
    _feed = feed;
    state = state.copyWith(link: PresenceLink.connecting);

    _linkSub = feed.link.listen((link) {
      // Ignore late frames after the guard has stopped streaming.
      if (state.streaming) state = state.copyWith(link: link);
    });
    await feed.connect();
    // A teardown (goOffline / stopJobStreaming / logout) may have raced in during the await —
    // _teardown ran and already closed the feed, but it could not cancel _posSub (not assigned
    // yet). Bail before subscribing so we never orphan a GPS subscription that streams to a closed
    // feed.
    if (_feed == null || !state.streaming) return;

    _posSub = ref.read(locationServiceProvider).positionStream().listen((s) {
      if (!state.streaming) return;
      feed.sendLocation(s);
      state = state.copyWith(lastSample: s);
    });

    // Stay fresh from t=0: the movement-gated positionStream may never emit while the guard sits
    // still waiting for a job, so push a one-shot CURRENT fix immediately — the guard is
    // discoverable without having to move first.
    await _pushCurrentFix();
    // Keep fresh while stationary: re-send a current fix on a cadence well under the presence
    // 5-min freshness window so `recorded_at` never goes stale and the guard stays in
    // `online-guards`. Cancelled in _teardown. (One-shot getCurrentPosition, not a high-rate
    // stream — battery-sane; the movement stream above still carries live motion updates.)
    _keepalive ??= Timer.periodic(_keepaliveInterval, (_) => _pushCurrentFix());
  }

  /// Push the latest available GPS fix to presence to keep `recorded_at` fresh: prefer a fresh
  /// one-shot fix (accurate), else fall back to the last sample we already have. Sends nothing when
  /// streaming has stopped (a teardown may have raced in during the await) or when no fix is
  /// available at all (e.g. permission denied → [LocationService.currentSample] returns `null` and
  /// there is no prior sample). Never throws.
  Future<void> _pushCurrentFix() async {
    if (!state.streaming) return;
    final fresh = await ref.read(locationServiceProvider).currentSample();
    final feed = _feed;
    // Re-check after the async fix: a teardown (goOffline / stopJobStreaming / logout) may have run
    // while awaiting, closing the feed — never send to a closed feed.
    if (feed == null || !state.streaming) return;
    // Prefer a fresh one-shot fix; else fall back to the cached one ONLY while it is still inside
    // the presence freshness window — never re-broadcast a stale fix as the guard's current spot.
    // No fresh fix and nothing (fresh enough) cached → nothing to send.
    final sample = fresh ?? _freshCachedSample();
    if (sample == null) return;
    feed.sendLocation(sample);
    state = state.copyWith(lastSample: sample);
  }

  /// The last cached fix, but only if it is younger than [_maxCachedFixAge] — otherwise `null` so
  /// the keepalive sends nothing rather than advertising a stale position as current.
  GpsSample? _freshCachedSample() {
    final cached = state.lastSample;
    if (cached == null) return null;
    final age = DateTime.now().toUtc().difference(cached.recordedAt.toUtc());
    return age <= _maxCachedFixAge ? cached : null;
  }

  /// Tear down the feed/stream only when nothing wants GPS anymore (toggle off AND no job lease),
  /// resetting the link + last sample. Keeps streaming alive while any lease remains.
  Future<void> _teardownIfIdle() async {
    if (state.streaming) return;
    await _teardown();
    state = state.copyWith(link: PresenceLink.offline, lastSample: null);
  }

  /// Full stop (logout): drop the manual toggle AND all job leases, then tear down.
  Future<void> _shutDown() async {
    await _teardown();
    state = const TrackingState();
  }

  Future<void> _teardown() async {
    _keepalive?.cancel();
    _keepalive = null;
    await _posSub?.cancel();
    await _linkSub?.cancel();
    _posSub = null;
    _linkSub = null;
    final feed = _feed;
    _feed = null;
    await feed?.close();
  }
}
