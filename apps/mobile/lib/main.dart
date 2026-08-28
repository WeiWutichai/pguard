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
import 'core/providers.dart';
import 'core/storage/first_run.dart';
import 'core/storage/secure_store.dart';

/// Background / terminated FCM handler — MUST be a top-level (or static) function. We don't navigate
/// here (no live UI); Android auto-displays the `notification` block in the tray, and the tap is
/// routed by the push controller via getInitialMessage / onMessageOpenedApp once the app resumes.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Kick the fresh-install secure-store WIPE (iOS Keychain survives uninstall — v1 risk 3.2) but do
  // NOT block the first paint on it (perf-review #7). The session classifier awaits this same future
  // (via `appBootstrapProvider`) BEFORE it reads any stored token, so a reinstall still can't
  // classify from the prior owner's tokens — the ordering is preserved while the splash paints
  // immediately. Best-effort: a wipe failure never strands startup.
  final bootstrap = _firstRunWipe();
  runApp(ProviderScope(
    overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
    child: const PGuardApp(),
  ));
  // The native init steps (local-notification channel + Firebase) run AFTER the first frame so the
  // splash appears instantly instead of waiting on Firebase.initializeApp (~hundreds of ms) + the
  // channel setup. Both degrade gracefully and nothing consumes them before the session is
  // authenticated (a user-driven, post-splash transition), so deferring them is safe.
  WidgetsBinding.instance.addPostFrameCallback((_) => _initNativeServices());
}

/// Fresh-install token wipe (best-effort — a wedged keystore must not strand startup).
Future<void> _firstRunWipe() async {
  try {
    await const FirstRunGuard().wipeIfFreshInstall(SecureStore());
  } catch (_) {
    // Proceed — the session classifier fail-safes an unreadable/unwritable store to the login flow.
  }
}

/// Post-first-frame native init: the Android "default" notification channel (HIGH importance + sound
/// so pushes chime on Android 8+; the server tags every push with channel_id="default") and Firebase
/// push. Both are best-effort — a missing google-services.json / no Firebase just means "no push".
Future<void> _initNativeServices() async {
  final localNotifications = LocalNotifications();
  try {
    await localNotifications.init();
  } catch (_) {
    // Local-notification channel setup failed → pushes may not chime; the app still runs.
  }
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
}
