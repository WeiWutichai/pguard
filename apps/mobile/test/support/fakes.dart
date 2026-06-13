import 'dart:async';
import 'dart:convert';

import 'package:pguard_mobile/core/calling/call_engine.dart';
import 'package:pguard_mobile/core/location/location_service.dart';
import 'package:pguard_mobile/core/media/chat_attachment_service.dart';
import 'package:pguard_mobile/core/media/chat_media_picker.dart';
import 'package:pguard_mobile/core/media/document_picker.dart';
import 'package:pguard_mobile/core/media/photo_capture.dart';
import 'package:pguard_mobile/core/models/booking.dart';
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
import 'package:pguard_mobile/core/storage/prefs_store.dart';
import 'package:pguard_mobile/core/storage/secure_store.dart';

/// In-memory [AppStore] for tests — keeps the app off platform channels (FlutterSecureStorage).
class InMemoryStore implements AppStore {
  String? access;
  String? refresh;
  String? phone;
  String? phoneVerifiedToken;
  String? profileToken;
  String? pinHash;
  String? pinSalt;
  int attempts = 0;
  int? lockUntil;
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
  Future<void> clearSession() async {
    access = null;
    refresh = null;
    phone = null;
    phoneVerifiedToken = null;
    profileToken = null;
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
  Future<void> wipe() async {
    access = null;
    refresh = null;
    phone = null;
    pinHash = null;
    pinSalt = null;
    attempts = 0;
    lockUntil = null;
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
class FakeApi implements PguardApi {
  FakeApi({this.onGet, this.onPost, this.onPut});

  final Future<dynamic> Function(String path, Map<String, dynamic>? query)?
      onGet;
  final Future<dynamic> Function(String path, Object? data)? onPost;
  final Future<dynamic> Function(String path, Object? data)? onPut;

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
  Future<String?> validAccessToken() async => 'test-access-token';

  int get getCount => calls.where((c) => c.startsWith('GET')).length;
}

/// Fake [BookingStatusFeed] — tests push events synchronously to drive the controller without
/// any real WebSocket.
class FakeBookingFeed implements BookingStatusFeed {
  final StreamController<BookingStatusEvent> _controller =
      StreamController<BookingStatusEvent>.broadcast();
  bool connected = false;
  bool closed = false;

  @override
  Stream<BookingStatusEvent> get events => _controller.stream;

  @override
  Future<void> connect() async => connected = true;

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }

  void emit(BookingStatusEvent event) => _controller.add(event);
}

/// Fake [ChatFeed] — tests push incoming messages synchronously and inspect what was sent,
/// without any real WebSocket.
class FakeChatFeed implements ChatFeed {
  final StreamController<ChatMessage> _controller =
      StreamController<ChatMessage>.broadcast();

  /// Frames passed to [sendMessage], in order (so tests assert the outbound payload).
  final List<Map<String, dynamic>> sent = [];
  bool connected = false;
  bool closed = false;

  @override
  Stream<ChatMessage> get messages => _controller.stream;

  @override
  Future<void> connect() async => connected = true;

  @override
  void sendMessage({
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
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }

  void emit(ChatMessage message) => _controller.add(message);
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

  void emit(GpsSample sample) => _positions.add(sample);

  @override
  Stream<GpsSample> positionStream() => _positions.stream;

  @override
  Future<GeoPoint?> currentLocation() async => current;

  @override
  Future<String> reverseGeocode(GeoPoint point) async => 'fake place';
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

/// Build an UNSIGNED-but-well-formed JWT with the given claims (for client `exp`/`role`
/// decoding tests — the client never verifies the signature).
String fakeJwt(Map<String, dynamic> claims) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg({'alg': 'HS256', 'typ': 'JWT'});
  final payload = seg(claims);
  return '$header.$payload.sig';
}
