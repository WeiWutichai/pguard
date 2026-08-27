import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/core/calling/call_engine.dart';
import 'package:pguard_mobile/core/controllers/biometric_service.dart';
import 'package:pguard_mobile/core/location/location_service.dart';
import 'package:pguard_mobile/core/location/routing_service.dart';
import 'package:pguard_mobile/core/media/chat_attachment_service.dart';
import 'package:pguard_mobile/core/media/chat_media_picker.dart';
import 'package:pguard_mobile/core/media/document_picker.dart';
import 'package:pguard_mobile/core/media/photo_capture.dart';
import 'package:pguard_mobile/core/media/slip_picker.dart';
import 'package:pguard_mobile/core/push/push_service.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/permissions/permission_gate.dart';
import 'package:pguard_mobile/core/models/call.dart';
import 'package:pguard_mobile/core/models/chat.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/core/models/tracking.dart';
import 'package:pguard_mobile/core/network/api_client.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/network/check_in_service.dart';
import 'package:pguard_mobile/core/network/sockets/booking_status_socket.dart';
import 'package:pguard_mobile/core/network/sockets/call_socket.dart';
import 'package:pguard_mobile/core/network/sockets/chat_socket.dart';
import 'package:pguard_mobile/core/network/sockets/presence_socket.dart';
import 'package:pguard_mobile/core/pdf/document_sharer.dart';
import 'package:pguard_mobile/core/storage/prefs_store.dart';
import 'package:pguard_mobile/core/storage/secure_store.dart';

/// In-memory [AppStore] for tests — keeps the app off platform channels (FlutterSecureStorage).
class InMemoryStore implements AppStore {
  String? access;
  String? refresh;
  String? phone;
  String? phoneVerifiedToken;
  String? profileToken;
  String? onboardingPin;
  String? pinHash;
  String? pinSalt;
  int attempts = 0;
  int? lockUntil;
  bool biometricEnabled = false;
  bool wiped = false;

  @override
  Future<String?> readAccessToken() async => access;
  @override
  Future<String?> readRefreshToken() async => refresh;
  @override
  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<String?> readPhone() async => phone;
  @override
  Future<void> savePhone(String phone) async => this.phone = phone;

  @override
  Future<String?> readPhoneVerifiedToken() async => phoneVerifiedToken;
  @override
  Future<void> savePhoneVerifiedToken(String token) async =>
      phoneVerifiedToken = token;
  @override
  Future<String?> readProfileToken() async => profileToken;
  @override
  Future<void> saveProfileToken(String token) async => profileToken = token;
  @override
  Future<void> clearRegistrationTokens() async {
    phoneVerifiedToken = null;
    profileToken = null;
  }

  @override
  Future<void> clearPhoneVerifiedToken() async => phoneVerifiedToken = null;

  @override
  Future<String?> readOnboardingPin() async => onboardingPin;
  @override
  Future<void> saveOnboardingPin(String pin) async => onboardingPin = pin;
  @override
  Future<void> clearOnboardingPin() async => onboardingPin = null;

  @override
  Future<void> clearSession() async {
    access = null;
    refresh = null;
    phone = null;
    onboardingPin = null;
    phoneVerifiedToken = null;
    profileToken = null;
  }

  @override
  Future<void> clearTokens() async {
    access = null;
    refresh = null;
  }

  @override
  Future<bool> hasPin() async => pinHash != null;
  @override
  Future<String?> readPinHash() async => pinHash;
  @override
  Future<String?> readPinSalt() async => pinSalt;
  @override
  Future<void> savePin({required String hash, required String salt}) async {
    pinHash = hash;
    pinSalt = salt;
    attempts = 0;
    lockUntil = null;
  }

  @override
  Future<int> readPinAttempts() async => attempts;
  @override
  Future<void> writePinAttempts(int value) async => attempts = value;
  @override
  Future<void> resetPinAttempts() async {
    attempts = 0;
    lockUntil = null;
  }

  @override
  Future<int?> readPinLockUntilMs() async => lockUntil;
  @override
  Future<void> writePinLockUntilMs(int? epochMs) async => lockUntil = epochMs;

  @override
  Future<bool> isBiometricEnabled() async => biometricEnabled;
  @override
  Future<void> setBiometricEnabled(bool value) async =>
      biometricEnabled = value;

  @override
  Future<void> wipe() async {
    access = null;
    refresh = null;
    phone = null;
    pinHash = null;
    pinSalt = null;
    attempts = 0;
    lockUntil = null;
    biometricEnabled = false;
    wiped = true;
  }
}

/// In-memory [PrefsStore] for tests (no platform channels).
class FakePrefsStore implements PrefsStore {
  final Map<String, String> values = {};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// Configurable fake [PguardApi] with per-method handlers and a call log (to prove there is
/// NO polling — the live-status path should fetch REST exactly once).
/// Minimal [PushService] stub for tests that just need the provider off real Firebase (e.g. logout,
/// which unregisters the FCM token). Records how many times [deleteToken] ran.
class StubPush implements PushService {
  StubPush({this.token = 'fcm-tok'});
  final String? token;
  int deleteTokenCalls = 0;

  @override
  Future<void> requestPermission() async {}
  @override
  Future<String?> getToken() async => token;
  @override
  Future<void> deleteToken() async => deleteTokenCalls++;
  @override
  Stream<String> get tokenRefreshes => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get foregroundMessages => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get openedMessages => const Stream.empty();
  @override
  Future<Map<String, dynamic>?> initialMessageData() async => null;
}

class FakeApi implements PguardApi {
  FakeApi({this.onGet, this.onPost, this.onPut, this.onPatch, this.onDelete});

  final Future<dynamic> Function(String path, Map<String, dynamic>? query)?
      onGet;
  final Future<dynamic> Function(String path, Object? data)? onPost;
  final Future<dynamic> Function(String path, Object? data)? onPut;
  final Future<dynamic> Function(String path, Object? data)? onPatch;
  final Future<dynamic> Function(String path, Object? data)? onDelete;

  final List<String> calls = [];

  /// The explicit `bearer` override passed to each `post` (keyed by path) — lets tests assert
  /// the profile submit carried the single-use `profile_token` rather than the session token.
  final Map<String, String?> postBearer = {};

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    calls.add('GET $path');
    return onGet!(path, query);
  }

  @override
  Future<dynamic> post(String path, {Object? data, String? bearer}) {
    calls.add('POST $path');
    postBearer[path] = bearer;
    return onPost!(path, data);
  }

  @override
  Future<dynamic> put(String path, {Object? data}) {
    calls.add('PUT $path');
    return onPut!(path, data);
  }

  @override
  Future<dynamic> patch(String path, {Object? data}) {
    calls.add('PATCH $path');
    return onPatch!(path, data);
  }

  @override
  Future<dynamic> delete(String path, {Object? data}) {
    calls.add('DELETE $path');
    // Tolerate tests that don't wire onDelete (e.g. logout's best-effort token unregister).
    return onDelete?.call(path, data) ?? Future.value(null);
  }

  @override
  Future<String?> validAccessToken() async => 'test-access-token';

  int get getCount => calls.where((c) => c.startsWith('GET')).length;
}

/// Fake [BookingStatusFeed] — tests push events synchronously to drive the controller without
/// any real WebSocket.
class FakeBookingFeed implements BookingStatusFeed {
  final StreamController<BookingStatusEvent> _controller =
      StreamController<BookingStatusEvent>.broadcast();
  final StreamController<bool> _connController =
      StreamController<bool>.broadcast();
  bool connected = false;
  bool closed = false;

  @override
  Stream<BookingStatusEvent> get events => _controller.stream;

  @override
  Stream<bool> get connectionChanges => _connController.stream;

  @override
  Future<void> connect() async => connected = true;

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
    if (!_connController.isClosed) await _connController.close();
  }

  void emit(BookingStatusEvent event) => _controller.add(event);

  /// Drive a connection-state edge (tests simulate a WS drop → reconnect).
  void emitConnection(bool connected) => _connController.add(connected);
}

/// Fake [ChatFeed] — tests push incoming messages synchronously and inspect what was sent,
/// without any real WebSocket.
class FakeChatFeed implements ChatFeed {
  final StreamController<ChatMessage> _controller =
      StreamController<ChatMessage>.broadcast();
  final StreamController<ChatWsError> _errors =
      StreamController<ChatWsError>.broadcast();
  final StreamController<bool> _connController =
      StreamController<bool>.broadcast();

  /// Frames passed to [sendMessage], in order (so tests assert the outbound payload).
  final List<Map<String, dynamic>> sent = [];
  bool connected = false;
  bool closed = false;

  /// What [sendMessage] returns — flip to `false` to simulate a send while the socket is DOWN
  /// (the frame is dropped) so tests can assert the composer keeps the text + surfaces a hint.
  bool sendResult = true;

  @override
  Stream<ChatMessage> get messages => _controller.stream;

  @override
  Stream<ChatWsError> get errors => _errors.stream;

  @override
  Stream<bool> get connectionChanges => _connController.stream;

  @override
  Future<void> connect() async => connected = true;

  @override
  bool sendMessage({
    required String conversationId,
    String? content,
    required ChatMessageType type,
    required ChatRole senderRole,
  }) {
    // Mirror ChatSocket's conditional inclusion (omit `content` when null) so the fake's recorded
    // frame matches the real wire frame exactly.
    sent.add({
      'conversation_id': conversationId,
      if (content != null) 'content': content,
      'message_type': type.wire,
      'sender_role': senderRole.wire,
    });
    return sendResult;
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
    if (!_errors.isClosed) await _errors.close();
    if (!_connController.isClosed) await _connController.close();
  }

  void emit(ChatMessage message) => _controller.add(message);

  /// Push a server ERROR frame (a rejected send), e.g.
  /// `emitError(const ChatWsError(code: 'read_only', message: 'Conversation is read-only'))`.
  void emitError(ChatWsError error) => _errors.add(error);

  /// Drive a connection-state edge (tests simulate a WS drop → reconnect to exercise the
  /// history re-pull).
  void emitConnection(bool connected) => _connController.add(connected);
}

/// Fake [ChatAttachmentService] — returns a canned attachment (or throws a canned error) and
/// records the requested sources.
class FakeChatAttachmentService implements ChatAttachmentService {
  FakeChatAttachmentService({this.attachment, this.error});

  final Attachment? attachment;
  final Object? error;
  final List<ChatAttachmentSource> picks = [];

  @override
  Future<Attachment?> pickAndUpload(
      String conversationId, ChatAttachmentSource source,
      {required bool isThai}) async {
    picks.add(source);
    if (error != null) throw error!;
    return attachment;
  }
}

/// Fake [ChatMediaPicker] — records the requested sources and returns a canned media (or null
/// to simulate the user cancelling). Stands in for the real `image_picker` in service tests.
class FakeChatMediaPicker implements ChatMediaPicker {
  FakeChatMediaPicker({this.media});

  PickedMedia? media;
  final List<ChatAttachmentSource> picks = [];

  @override
  Future<PickedMedia?> pick(ChatAttachmentSource source) async {
    picks.add(source);
    return media;
  }
}

/// Fake [PresenceFeed] — records the GPS samples streamed up and lets tests drive link state.
class FakePresenceFeed implements PresenceFeed {
  final StreamController<PresenceLink> _link =
      StreamController<PresenceLink>.broadcast();
  final List<GpsSample> sent = [];
  bool connected = false;
  bool closed = false;

  @override
  Stream<PresenceLink> get link => _link.stream;

  @override
  Future<void> connect() async {
    connected = true;
    _link.add(PresenceLink.online);
  }

  @override
  void sendLocation(GpsSample sample) => sent.add(sample);

  @override
  Future<void> close() async {
    closed = true;
    if (!_link.isClosed) await _link.close();
  }

  void emitLink(PresenceLink link) => _link.add(link);
}

/// Fake [LocationService] — a controllable GPS position stream (no native channels).
class FakeLocationService implements LocationService {
  final StreamController<GpsSample> _positions =
      StreamController<GpsSample>.broadcast();

  /// What [currentLocation] resolves to (settable; `null` = no GPS fix).
  GeoPoint? current = GeoPoint.bangkok;

  /// What the one-shot [currentSample] resolves to (settable; `null` = no fix / permission denied,
  /// e.g. to test that the keepalive sends nothing). Defaults to a high-accuracy Bangkok fix so the
  /// start-fix + keepalive paths have something to send. Counts calls so tests can assert how many
  /// one-shot fixes were taken (start fix + each keepalive tick).
  GpsSample? sample = GpsSample(
      lat: 13.7, lng: 100.5, accuracy: 8, recordedAt: DateTime.utc(2026));
  int sampleCount = 0;

  void emit(GpsSample sample) => _positions.add(sample);

  @override
  Stream<GpsSample> positionStream() => _positions.stream;

  @override
  Future<GeoPoint?> currentLocation() async => current;

  @override
  Future<GpsSample?> currentSample() async {
    sampleCount++;
    return sample;
  }

  @override
  Stream<GeoPoint?> selfLocationStream() async* {
    yield current;
    yield* _positions.stream.map((s) => GeoPoint(s.lat, s.lng));
  }

  @override
  Future<String> reverseGeocode(GeoPoint point) async => 'fake place';
}

/// Fake [RoutingService] — returns a canned [RouteResult] (or null to force the straight-line
/// fallback) and records the requested origin/dest pairs. No network. By default returns null so a
/// test that doesn't care about routing gets the deterministic straight-line behaviour.
class FakeRoutingService implements RoutingService {
  FakeRoutingService({this.result});

  /// What every [route] call resolves to (`null` = no route → caller degrades to straight line).
  RouteResult? result;
  final List<({GeoPoint origin, GeoPoint dest})> calls = [];

  @override
  Future<RouteResult?> route({
    required GeoPoint origin,
    required GeoPoint dest,
  }) async {
    calls.add((origin: origin, dest: dest));
    return result;
  }
}

/// Fake [CheckInService] — records submissions; optionally fails.
class FakeCheckInService implements CheckInService {
  FakeCheckInService({this.fail = false});

  final bool fail;
  final List<int> submitted = [];

  @override
  Future<void> submit({
    required String bookingId,
    required int hourNumber,
    required CapturedPhoto photo,
    required bool isThai,
    GpsSample? gps,
    String? note,
  }) async {
    if (fail) throw const ApiException(message: 'check-in failed');
    submitted.add(hourNumber);
  }
}

/// Fake [PhotoCaptureService] — returns a canned photo.
class FakePhotoCaptureService implements PhotoCaptureService {
  @override
  Future<CapturedPhoto?> capture() async =>
      const CapturedPhoto(path: '/tmp/checkpoint.jpg', sizeBytes: 1024);
}

/// Fake [DocumentPicker] — records the requested sources and returns a canned path (or null to
/// simulate the user cancelling). Stands in for the real `image_picker` in widget tests.
class FakeDocumentPicker implements DocumentPicker {
  FakeDocumentPicker({this.path = '/tmp/doc.jpg'});

  String? path;
  final List<DocSource> picks = [];

  @override
  Future<String?> pick(DocSource source) async {
    picks.add(source);
    return path;
  }
}

/// Fake [SlipPicker] — records the requested sources and returns a canned path (or null to
/// simulate the user cancelling). Stands in for the real `image_picker` in the slip-pay tests.
class FakeSlipPicker implements SlipPicker {
  FakeSlipPicker({this.path = '/tmp/slip.jpg'});

  String? path;
  final List<SlipSource> picks = [];

  @override
  Future<String?> pick(SlipSource source) async {
    picks.add(source);
    return path;
  }
}

/// Fake [CallEngine] — records the WebRTC operations and lets tests drive media/ICE events,
/// with NO `flutter_webrtc` plugin (keeps the call controller off platform channels).
class FakeCallEngine implements CallEngine {
  FakeCallEngine({this.throwOnInit});

  /// When set, [initialize] throws this (e.g. a denied-permission [CallException]).
  final Object? throwOnInit;

  bool initialized = false;
  bool? initVideo;
  List<IceServer>? initIceServers;
  bool disposed = false;
  bool? muted;
  bool? speakerOn;
  int switchCameraCount = 0;
  int createOfferCount = 0;
  int createAnswerCount = 0;
  final List<SignalDescription> remoteDescriptions = [];
  final List<SignalCandidate> addedCandidates = [];

  Object? _localStream;
  Object? _remoteStream;

  final _localCand = StreamController<SignalCandidate>.broadcast();
  final _mediaEvent = StreamController<CallMediaEvent>.broadcast();
  final _remoteChanged = StreamController<void>.broadcast();

  @override
  Future<void> initialize({
    required bool video,
    required List<IceServer> iceServers,
  }) async {
    if (throwOnInit != null) throw throwOnInit!;
    initialized = true;
    initVideo = video;
    initIceServers = iceServers;
  }

  @override
  Future<SignalDescription> createOffer() async {
    createOfferCount++;
    return const SignalDescription(type: 'offer', sdp: 'OFFER_SDP');
  }

  @override
  Future<SignalDescription> createAnswer() async {
    createAnswerCount++;
    return const SignalDescription(type: 'answer', sdp: 'ANSWER_SDP');
  }

  @override
  Future<void> setRemoteDescription(SignalDescription description) async =>
      remoteDescriptions.add(description);

  @override
  Future<void> addIceCandidate(SignalCandidate candidate) async =>
      addedCandidates.add(candidate);

  @override
  Stream<SignalCandidate> get onLocalCandidate => _localCand.stream;
  @override
  Stream<CallMediaEvent> get onMediaEvent => _mediaEvent.stream;
  @override
  Stream<void> get onRemoteStreamChanged => _remoteChanged.stream;

  @override
  Future<void> setMuted(bool m) async => muted = m;
  @override
  Future<void> setSpeaker(bool on) async => speakerOn = on;
  @override
  Future<void> switchCamera() async => switchCameraCount++;

  @override
  Object? get localStream => _localStream;
  @override
  Object? get remoteStream => _remoteStream;

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!_localCand.isClosed) await _localCand.close();
    if (!_mediaEvent.isClosed) await _mediaEvent.close();
    if (!_remoteChanged.isClosed) await _remoteChanged.close();
  }

  // Test drivers.
  void emitLocalCandidate(SignalCandidate c) => _localCand.add(c);
  void emitMediaEvent(CallMediaEvent e) => _mediaEvent.add(e);
  void emitRemoteStream(Object? stream) {
    _remoteStream = stream;
    _remoteChanged.add(null);
  }
}

/// Fake [CallSignalFeed] — records sent signals and lets tests push inbound relay frames, with
/// no real WebSocket.
class FakeCallSignalFeed implements CallSignalFeed {
  final StreamController<CallSignalFrame> _controller =
      StreamController<CallSignalFrame>.broadcast();

  /// Signals passed to [send], in order (callId + the [CallSignal]).
  final List<({String callId, CallSignal signal})> sent = [];
  bool connected = false;
  bool closed = false;

  @override
  Stream<CallSignalFrame> get signals => _controller.stream;

  @override
  Future<void> connect() async => connected = true;

  @override
  void send({required String callId, required CallSignal signal}) =>
      sent.add((callId: callId, signal: signal));

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }

  void emit(CallSignalFrame frame) => _controller.add(frame);

  /// Convenience: emit a relay frame for [callId] carrying [signal].
  void emitSignal(String callId, CallSignal signal, {String? from}) =>
      emit(CallSignalFrame(callId: callId, signal: signal, from: from));
}

/// Fake [BiometricAuthenticator] — drives capability + the prompt result with no platform
/// channels, and records how many times the OS prompt was invoked (to assert auto-prompt).
class FakeBiometricAuthenticator implements BiometricAuthenticator {
  FakeBiometricAuthenticator({
    this.deviceSupported = true,
    this.canCheck = true,
    bool? enrolled,
    this.authResult = true,
  }) : enrolled = enrolled ?? canCheck;

  bool deviceSupported;
  bool canCheck;

  /// Whether a biometric is actually ENROLLED (defaults to [canCheck] so existing tests that only
  /// set canCheck keep behaving as "available"; set false to simulate a sensor with no enrolment).
  bool enrolled;
  bool authResult;
  int authCalls = 0;
  String? lastReason;

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;
  @override
  Future<bool> canCheckBiometrics() async => canCheck;
  @override
  Future<bool> hasEnrolledBiometrics() async => enrolled;
  @override
  Future<bool> authenticate({required String localizedReason}) async {
    authCalls++;
    lastReason = localizedReason;
    return authResult;
  }
}

/// Build an UNSIGNED-but-well-formed JWT with the given claims (for client `exp`/`role`
/// decoding tests — the client never verifies the signature).
String fakeJwt(Map<String, dynamic> claims) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg({'alg': 'HS256', 'typ': 'JWT'});
  final payload = seg(claims);
  return '$header.$payload.sig';
}

/// In-memory [PermissionGate] for the location-permission tests. [status] is the current OS
/// answer; [requestResult] (if set) is what `requestLocation()` flips it to. Counts calls.
class FakePermissionGate implements PermissionGate {
  FakePermissionGate(this.status, {this.requestResult});

  PgPermissionState status;
  PgPermissionState? requestResult;
  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<PgPermissionState> locationStatus() async => status;

  @override
  Future<PgPermissionState> requestLocation() async {
    requestCount++;
    if (requestResult != null) status = requestResult!;
    return status;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCount++;
    return true;
  }
}

/// In-memory [DocumentSharer] — records the bytes and filename the app would have handed to the
/// OS, so the receipt download is exercisable end-to-end (the PDF is REALLY built) without the
/// `path_provider` / `share_plus` platform channels. Set [throwOnShare] to drive the failure path;
/// set [hold] to keep the share in flight so the caller's in-progress UI can be inspected.
class FakeDocumentSharer implements DocumentSharer {
  Uint8List? bytes;
  String? fileName;
  String? mimeType;
  String? subject;
  int calls = 0;
  bool throwOnShare = false;

  /// When set, `shareBytes` records its arguments and then blocks until [release] — the app stays
  /// in its "working…" state deterministically, instead of the test racing a real future.
  Completer<void>? hold;

  void release() => hold?.complete();

  @override
  Future<void> shareBytes({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/pdf',
    String? subject,
  }) async {
    calls++;
    this.bytes = bytes;
    this.fileName = fileName;
    this.mimeType = mimeType;
    this.subject = subject;
    if (hold != null) await hold!.future;
    if (throwOnShare) throw StateError('no share target');
  }
}

/// A `sessionProvider` override that boots straight into an AUTHENTICATED guard, so a widget test
/// can render a guard screen whose data (jobs/earnings) is scoped by the SESSION user id without
/// driving the whole login flow. `guardJobsController` reads identity from the session, so screens
/// that list a guard's jobs need this seeded BEFORE they build.
Override seededGuardSession() =>
    sessionProvider.overrideWith(_SeededGuardSession.new);

class _SeededGuardSession extends Session {
  @override
  SessionState build() => const SessionState(
        SessionStatus.authenticated,
        user: AuthUser(userId: 'g1', role: 'guard', roles: ['guard']),
      );
}
