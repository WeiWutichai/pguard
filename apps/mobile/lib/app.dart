import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/push/in_app_banner.dart';
import 'core/push/push_registration_controller.dart';
import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';

/// Root app widget: MaterialApp.router wired to the session-aware go_router and the
/// token-derived theme. Riverpod's ProviderScope is installed in main().
class PGuardApp extends ConsumerWidget {
  const PGuardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Instantiate the keepAlive push controller so it registers the FCM token + routes incoming
    // calls once the session is authenticated. (Value unused; this just keeps it alive.)
    ref.watch(pushRegistrationProvider);
    return MaterialApp.router(
      title: 'pguard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      // App-wide messenger so the context-free push layer can surface an in-app banner
      // (e.g. "New job nearby") over any screen — see core/push/in_app_banner.dart.
      scaffoldMessengerKey: rootMessengerKey,
    );
  }
}
