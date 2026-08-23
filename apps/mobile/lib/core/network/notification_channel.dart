// Android notification channel + foreground presentation (N3b — fix "no sound").
//
// THE BUG: the notification service sends every push with
//   android.notification { sound: "default", channel_id: "default" }   (services/notification/src/fcm.rs)
// but the app never created a channel with id "default". On Android 8+ (API 26) a notification whose
// channel does not exist is dropped onto an app-default channel with LOW importance and NO sound —
// so pushes arrived silently. Creating a HIGH-importance "default" channel here (id EXACTLY
// "default", matching the server) makes both background AND foreground pushes chime.
//
// Two Android facts this handles:
//   1. BACKGROUND / terminated: FCM auto-displays the `notification` block, but it uses the channel
//      named in the message (channel_id="default"). That channel must already EXIST on the device —
//      channels are registered here at app start.
//   2. FOREGROUND: FCM does NOT auto-display a notification while the app is foregrounded (onMessage
//      fires instead), so nothing chimed. We re-present it ourselves via flutter_local_notifications
//      on the "default" channel so it plays a sound like any other.
//
// Scope guard: this ADDS sound; it never touches the existing tap-routing. Background/terminated
// taps still flow through firebase_messaging (onMessageOpenedApp / getInitialMessage) in the push
// controller, untouched. A foreground-presented notification's tap is a no-op (the app is already
// open, and the push controller already surfaces an in-app banner for it).

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The channel id — MUST equal the server's `android.notification.channel_id` ("default", set in
/// services/notification/src/fcm.rs). A mismatch reintroduces the silent-push bug.
const String kDefaultChannelId = 'default';

/// Whether a FOREGROUND FCM message should raise a heads-up system notification (for the sound).
/// PURE — unit-testable without platform channels.
///
///  * A data-only push (no `notification` title/body) is a silent signal (e.g. `call_cancelled`
///    clearing a ring) — never present it.
///  * Call-control pushes (`incoming_call` / `call_cancelled`) drive dedicated in-app call UI, so a
///    tray notification on top would double up — skip them.
///  * Everything else with a visible title/body (check-in reminders, new jobs, payment, booking
///    status, chat, refunds …) chimes.
bool shouldPresentForeground({
  required String? type,
  required bool hasNotificationBlock,
}) {
  if (!hasNotificationBlock) return false;
  if (type == 'incoming_call' || type == 'call_cancelled') return false;
  return true;
}

/// Owns the local-notifications plugin: registers the "default" channel at startup and re-presents
/// foreground FCM messages on it. Best-effort throughout — a plugin/platform hiccup must never crash
/// startup or the message pipeline (the app already degrades gracefully to "no push").
class LocalNotifications {
  LocalNotifications([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const AndroidNotificationChannel _defaultChannel =
      AndroidNotificationChannel(
    kDefaultChannelId,
    'ทั่วไป', // "General" — user-visible channel name in system settings.
    description: 'การแจ้งเตือนทั่วไป เช่น งานใหม่ การชำระเงิน และการเช็คอิน',
    importance: Importance.high, // heads-up + sound on API 26+
    playSound: true,
  );

  /// Initialize the plugin and register the HIGH-importance "default" channel. Idempotent
  /// (re-creating a channel with the same id just updates it). Call once from `main()`.
  Future<void> init() async {
    try {
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(initSettings);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_defaultChannel);
    } catch (_) {
      // No platform / plugin unavailable → the app still runs (silently) without local presentation.
    }
  }

  /// Present a FOREGROUND FCM message as a heads-up notification on the "default" channel so it
  /// plays a sound. No-ops for silent/data-only and call-control pushes (see
  /// [shouldPresentForeground]). Best-effort — never throws.
  Future<void> presentForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final type = message.data['type'] as String?;
    if (!shouldPresentForeground(
      type: type,
      hasNotificationBlock: notification != null,
    )) {
      return;
    }
    try {
      await _plugin.show(
        // A stable-ish id per message so distinct pushes stack rather than overwrite.
        message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
        notification!.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            kDefaultChannelId,
            'ทั่วไป',
            channelDescription:
                'การแจ้งเตือนทั่วไป เช่น งานใหม่ การชำระเงิน และการเช็คอิน',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {
      // Presentation is best-effort; a failure must not break the message pipeline.
    }
  }
}
