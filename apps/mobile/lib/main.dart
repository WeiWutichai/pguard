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
  // Firebase push is best-effort: a missing/invalid config (e.g. a dev build without
  // google-services.json) must NOT block startup — the app just runs without push.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  } catch (_) {
    // No Firebase available → continue; the push controller also degrades gracefully.
  }
  runApp(const ProviderScope(child: PGuardApp()));
}
