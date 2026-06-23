import 'package:flutter/material.dart';

/// Global [ScaffoldMessenger] key so a context-free layer (the push controller) can surface an
/// in-app banner — e.g. "New job nearby" — without holding a widget BuildContext. Attached to the
/// root `MaterialApp.router` in `app.dart`. The production [showInAppBanner] reads this key; tests
/// override the `pushNotify` provider with a recorder, so this key is never touched under test.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Surface [message] as a SnackBar over whatever screen is showing, using the app-wide
/// [rootMessengerKey]. Best-effort: a null messenger (before the first frame / under test) is a
/// no-op, never a crash.
void showInAppBanner(String message) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
