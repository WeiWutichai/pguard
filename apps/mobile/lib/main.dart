// pguard v2 scaffold stub — app entry point.
// See ../../CLAUDE.md "Flutter (mobile)" Do/Don't.
//
// Conventions enforced here:
//   - Riverpod 2.x ProviderScope wraps the app (no Provider/ChangeNotifier).
//   - Booking/assignment status arrives via WebSocket subscription, NOT
//     Timer.periodic REST polling. WS lifecycle lives in
//     lib/core/network/sockets/, never inside screen state.
//   - Pure logic (countdown math, proration, state machines) belongs in
//     lib/core/controllers/, not in widgets.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  // TODO: bootstrap secure storage, dio client, and router before runApp.
  runApp(const ProviderScope(child: PGuardApp()));
}

class PGuardApp extends StatelessWidget {
  const PGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: replace MaterialApp with MaterialApp.router(go_router) once the
    // route table lands. Wire bilingual TH/EN localizationsDelegates here.
    return MaterialApp(
      title: 'pguard',
      theme: ThemeData(useMaterial3: true),
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    // TODO: replace with the real home/feature shell. Use the shared
    // PGuardHeader widget (lib/widgets/) — do not copy-paste header markup.
    return const Scaffold(
      body: Center(child: Text('pguard mobile — scaffold')),
    );
  }
}
