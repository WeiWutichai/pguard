// pguard v2 mobile — app entry point (Phase 2: push-based real-time).
// See ../../CLAUDE.md "Flutter (mobile)" Do/Don't.
//
// Conventions enforced across the app:
//   - Riverpod 2.x (@riverpod codegen) — no Provider/ChangeNotifier (see core/controllers/).
//   - Booking/assignment status arrives via WebSocket subscription (core/network/sockets/),
//     NOT Timer.periodic REST polling.
//   - Pure logic (state machines, lockout/proration/countdown math) lives in controllers,
//     not in widgets; tokens come from package:pguard_design_tokens.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/notification_channel.dart';
import 'core/storage/first_run.dart';
import 'core/storage/secure_store.dart';

/// Background / terminated FCM handler — MUST be a top-level (or static) function. We don't navigate
/// here (no live UI); Android auto-displays the `notification` block in the tray, and the tap is
/// routed by the push controller via getInitialMessage / onMessageOpenedApp once the app resumes.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clear any secure-store leftovers from a prior install BEFORE the session loads — iOS
  // Keychain survives uninstall, so a reinstall must start from a clean slate (v1 risk 3.2).
  await const FirstRunGuard().wipeIfFreshInstall(SecureStore());
  // Register the Android "default" notification channel (HIGH importance + sound) so pushes chime
  // on Android 8+ — the server tags every push with channel_id="default", which must EXIST on the
  // device. Independent of Firebase (local plugin) and best-effort, so it runs even if push is off.
  final localNotifications = LocalNotifications();
  await localNotifications.init();
  // Firebase push is best-effort: a missing/invalid config (e.g. a dev build without
  // google-services.json) must NOT block startup — the app just runs without push.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    // FCM does NOT auto-display a notification while the app is FOREGROUNDED — re-present it on the
    // "default" channel so it plays a sound (background/terminated are auto-shown by the OS on the
    // same channel). This is a SEPARATE listener from the push controller's in-app banner + does
    // NOT touch tap-routing (onMessageOpenedApp / getInitialMessage stay owned by the controller).
    FirebaseMessaging.onMessage
        .listen(localNotifications.presentForegroundMessage);
  } catch (_) {
    // No Firebase available → continue; the push controller also degrades gracefully.
  }
  runApp(const ProviderScope(child: PGuardApp()));
}
