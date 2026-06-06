import 'dart:async';
import 'dart:convert';

import 'package:pguard_mobile/core/location/location_service.dart';
import 'package:pguard_mobile/core/media/photo_capture.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/core/models/tracking.dart';
import 'package:pguard_mobile/core/network/api_client.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/network/check_in_service.dart';
import 'package:pguard_mobile/core/network/sockets/booking_status_socket.dart';
import 'package:pguard_mobile/core/network/sockets/presence_socket.dart';
import 'package:pguard_mobile/core/storage/prefs_store.dart';
import 'package:pguard_mobile/core/storage/secure_store.dart';

/// In-memory [AppStore] for tests — keeps the app off platform channels (FlutterSecureStorage).
class InMemoryStore implements AppStore {
  String? access;
  String? refresh;
  String? phone;
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
  Future<void> clearSession() async {
    access = null;
    refresh = null;
    phone = null;
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

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    calls.add('GET $path');
    return onGet!(path, query);
  }

  @override
  Future<dynamic> post(String path, {Object? data}) {
    calls.add('POST $path');
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

  void emit(GpsSample sample) => _positions.add(sample);

  @override
  Stream<GpsSample> positionStream() => _positions.stream;

  @override
  Future<GeoPoint?> currentLocation() async => GeoPoint.bangkok;

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

/// Build an UNSIGNED-but-well-formed JWT with the given claims (for client `exp`/`role`
/// decoding tests — the client never verifies the signature).
String fakeJwt(Map<String, dynamic> claims) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg({'alg': 'HS256', 'typ': 'JWT'});
  final payload = seg(claims);
  return '$header.$payload.sig';
}
