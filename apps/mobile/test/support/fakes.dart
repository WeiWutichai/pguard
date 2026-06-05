import 'dart:async';
import 'dart:convert';

import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/network/api_client.dart';
import 'package:pguard_mobile/core/network/sockets/booking_status_socket.dart';
import 'package:pguard_mobile/core/storage/secure_store.dart';

/// In-memory [AppStore] for tests — keeps the app off platform channels (FlutterSecureStorage).
class InMemoryStore implements AppStore {
  String? access;
  String? refresh;
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
  Future<void> clearSession() async {
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
  Future<void> wipe() async {
    access = null;
    refresh = null;
    pinHash = null;
    pinSalt = null;
    attempts = 0;
    lockUntil = null;
    wiped = true;
  }
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

/// Build an UNSIGNED-but-well-formed JWT with the given claims (for client `exp`/`role`
/// decoding tests — the client never verifies the signature).
String fakeJwt(Map<String, dynamic> claims) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg({'alg': 'HS256', 'typ': 'JWT'});
  final payload = seg(claims);
  return '$header.$payload.sig';
}
