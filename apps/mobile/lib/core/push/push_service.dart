import 'package:firebase_messaging/firebase_messaging.dart';

/// Device-push port — abstracts `FirebaseMessaging` so the registration controller is unit-testable
/// against a fake (no platform channels). Two message streams are exposed separately to avoid an
/// extra stream-merge dependency:
///  - [foregroundMessages]: `onMessage` data (app in the foreground).
///  - [openedMessages]: `onMessageOpenedApp` data (the user tapped the notification).
/// The terminated-state launch payload is read once via [initialMessageData].
abstract class PushService {
  /// Ask the OS for notification permission (Android 13+ / iOS). Best-effort; never throws.
  Future<void> requestPermission();

  /// The current FCM registration token, or null if unavailable.
  Future<String?> getToken();

  /// Delete this device's FCM token so the OS stops delivering to it (used on logout, after the
  /// backend row is removed, so a lingering push can't reach the logged-out device).
  Future<void> deleteToken();

  /// Emits a new token whenever FCM rotates it (must be re-registered with the backend).
  Stream<String> get tokenRefreshes;

  /// FCM `data` payloads delivered while the app is in the FOREGROUND.
  Stream<Map<String, dynamic>> get foregroundMessages;

  /// FCM `data` payloads from a notification TAP (app was backgrounded).
  Stream<Map<String, dynamic>> get openedMessages;

  /// The `data` payload that launched the app from a TERMINATED state (notification tap), once.
  Future<Map<String, dynamic>?> initialMessageData();
}

/// Production [PushService] backed by `FirebaseMessaging`.
class FirebasePushService implements PushService {
  FirebasePushService(this._fm);

  final FirebaseMessaging _fm;

  @override
  Future<void> requestPermission() async {
    await _fm.requestPermission();
  }

  @override
  Future<String?> getToken() => _fm.getToken();

  @override
  Future<void> deleteToken() => _fm.deleteToken();

  @override
  Stream<String> get tokenRefreshes => _fm.onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get foregroundMessages =>
      FirebaseMessaging.onMessage.map((m) => m.data);

  @override
  Stream<Map<String, dynamic>> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);

  @override
  Future<Map<String, dynamic>?> initialMessageData() async =>
      (await _fm.getInitialMessage())?.data;
}
