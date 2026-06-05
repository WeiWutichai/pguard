// pguard v2 mobile — app entry point (Phase 2: push-based real-time).
// See ../../CLAUDE.md "Flutter (mobile)" Do/Don't.
//
// Conventions enforced across the app:
//   - Riverpod 2.x (@riverpod codegen) — no Provider/ChangeNotifier (see core/controllers/).
//   - Booking/assignment status arrives via WebSocket subscription (core/network/sockets/),
//     NOT Timer.periodic REST polling.
//   - Pure logic (state machines, lockout/proration/countdown math) lives in controllers,
//     not in widgets; tokens come from package:pguard_design_tokens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/storage/first_run.dart';
import 'core/storage/secure_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clear any secure-store leftovers from a prior install BEFORE the session loads — iOS
  // Keychain survives uninstall, so a reinstall must start from a clean slate (v1 risk 3.2).
  await const FirstRunGuard().wipeIfFreshInstall(SecureStore());
  runApp(const ProviderScope(child: PGuardApp()));
}
