// Android notification channel + foreground presentation (N3 — fix "no sound").
//
// THE BUG: an earlier build registered the notification channel (id "default") with LOW importance
// and NO sound, so pushes arrived silently. The follow-up build corrected the channel to HIGH +
// sound — but nothing changed, because Android FREEZES a channel's importance and sound at FIRST
// creation: once "default" existed as a silent channel, re-creating it with the same id is ignored
// (the only way a user can change it afterwards is by hand in system settings).
//
// THE FIX (cache-bust): register a channel under a NEW id, "pguard_alerts_v2", created HIGH-
// importance + sound + vibration from the very first time — so Android honours the alerting
// settings. The server's `android.notification.channel_id` (services/notification/src/fcm.rs) is
// changed to the SAME "pguard_alerts_v2" id, and `init()` best-effort DELETES the stale "default"
// channel so it disappears from the app's notification settings. A mismatch between this id and the
// server's reintroduces the silent-push bug (an unknown channel falls back to low importance).
//
// Two Android facts this handles:
//   1. BACKGROUND / terminated: FCM auto-displays the `notification` block, but it uses the channel
//      named in the message (channel_id="pguard_alerts_v2"). That channel must already EXIST on the
//      device — it is registered here at app start.
//   2. FOREGROUND: FCM does NOT auto-display a notification while the app is foregrounded (onMessage
//      fires instead), so nothing chimed. We re-present it ourselves via flutter_local_notifications
//      on the same channel so it plays a sound like any other.
//
// Scope guard: this ADDS sound; it never touches the existing tap-routing. Background/terminated
// taps still flow through firebase_messaging (onMessageOpenedApp / getInitialMessage) in the push
// controller, untouched. A foreground-presented notification's tap is a no-op (the app is already
// open, and the push controller already surfaces an in-app banner for it).

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The channel id — MUST equal the server's `android.notification.channel_id`
/// ("pguard_alerts_v2", set in services/notification/src/fcm.rs) AND the AndroidManifest's
/// `default_notification_channel_id`. A mismatch reintroduces the silent-push bug. It is versioned
/// ("_v2") deliberately: Android freezes a channel's importance + sound at first creation, so
/// upgrading alerting settings requires a NEW id rather than editing the old one in place.
const String kDefaultChannelId = 'pguard_alerts_v2';

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
    enableVibration: true,
  );

  /// Initialize the plugin and register the HIGH-importance "pguard_alerts_v2" channel. NOTE: this
  /// is NOT idempotent for alerting settings — Android freezes a channel's importance + sound at
  /// FIRST creation, so re-creating an existing id with new settings is IGNORED (that is exactly why
  /// the id is versioned). We also best-effort DELETE the stale silent "default" channel so it stops
  /// showing in the app's notification settings. Call once from `main()`.
  Future<void> init() async {
    try {
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(initSettings);
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Remove the old silent channel first (cache-bust): it was frozen at LOW/no-sound on first
      // creation and can't be upgraded in place, so we retire the id entirely.
      await android?.deleteNotificationChannel('default');
      await android?.createNotificationChannel(_defaultChannel);
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
            enableVibration: true,
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
