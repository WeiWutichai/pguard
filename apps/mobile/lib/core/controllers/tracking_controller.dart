import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/tracking.dart';
import '../network/sockets/presence_socket.dart';
import '../providers.dart';
import 'session_controller.dart';

part 'tracking_controller.g.dart';

/// Guard presence state: whether the guard is online (visible to customers), the live
/// connection link, and the latest GPS fix (for the accuracy readout).
class TrackingState {
  const TrackingState({
    this.online = false,
    this.link = PresenceLink.offline,
    this.lastSample,
  });

  final bool online;
  final PresenceLink link;
  final GpsSample? lastSample;

  /// Qualitative accuracy band for the latest fix.
  GpsAccuracyBand get accuracyBand => GpsAccuracyBand.of(lastSample?.accuracy);

  /// Truly tracking = online, link up, AND at least one fix received.
  bool get isTracking =>
      online && link == PresenceLink.online && lastSample != null;

  TrackingState copyWith({
    bool? online,
    PresenceLink? link,
    GpsSample? lastSample,
  }) =>
      TrackingState(
        online: online ?? this.online,
        link: link ?? this.link,
        lastSample: lastSample ?? this.lastSample,
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

  @override
  TrackingState build() {
    ref.onDispose(_teardown);
    // Going offline must follow the guard out of the session — otherwise GPS keeps streaming
    // after logout (this provider is keepAlive and would survive the dashboard leaving).
    ref.listen(sessionProvider, (_, next) {
      if (next.status != SessionStatus.authenticated && state.online) {
        goOffline();
      }
    });
    return const TrackingState();
  }

  Future<void> toggle() => state.online ? goOffline() : goOnline();

  /// Go online: open the presence feed, reflect link state, and stream GPS fixes up.
  Future<void> goOnline() async {
    if (state.online) return;
    // Request location permission on EVERY go-online path — the card toggle AND the duty FAB land
    // here. Without it the OS allow dialog never shows (the FAB used to call this directly), the
    // position stream is empty, and the GPS line spins forever. Idempotent: when already granted
    // permission_handler returns immediately with no second dialog.
    await ref.read(permissionGateProvider).requestLocation();
    final api = ref.read(pguardApiProvider);
    final feed = ref.read(presenceFeedBuilderProvider)(api.validAccessToken);
    _feed = feed;
    state = state.copyWith(online: true, link: PresenceLink.connecting);

    _linkSub = feed.link.listen((link) {
      // Ignore late frames after the guard has gone offline.
      if (state.online) state = state.copyWith(link: link);
    });
    await feed.connect();
    // goOffline() may have raced in during the await — _teardown ran and already closed the
    // feed, but it could not cancel _posSub (not assigned yet). Bail before subscribing so we
    // never orphan a GPS subscription that streams to a closed feed.
    if (!state.online) return;

    _posSub = ref.read(locationServiceProvider).positionStream().listen((s) {
      if (!state.online) return;
      feed.sendLocation(s);
      state = state.copyWith(lastSample: s);
    });
  }

  /// Go offline (standby): stop streaming + close the feed.
  Future<void> goOffline() async {
    await _teardown();
    state = const TrackingState();
  }

  Future<void> _teardown() async {
    await _posSub?.cancel();
    await _linkSub?.cancel();
    _posSub = null;
    _linkSub = null;
    final feed = _feed;
    _feed = null;
    await feed?.close();
  }
}
