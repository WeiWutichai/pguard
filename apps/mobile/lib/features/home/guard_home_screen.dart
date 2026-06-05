import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/session_controller.dart';
import '../../widgets/pguard_header.dart';

/// Guard dashboard placeholder (role landing). The guard job flow is a later slice; this
/// confirms role-based routing works end-to-end.
class GuardHomeScreen extends ConsumerWidget {
  const GuardHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: PGuardHeader(
        title: 'pguard',
        subtitle: 'เจ้าหน้าที่ · Guard',
        trailing: IconButton(
          icon: const Icon(Icons.logout, color: Colors.white, size: 20),
          tooltip: 'Sign out',
          onPressed: () => ref.read(sessionProvider.notifier).logout(),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(PgTokens.space6),
          child: Text(
            'แดชบอร์ดเจ้าหน้าที่ — จะเพิ่มในสไลซ์ถัดไป\nGuard dashboard — coming in a later slice',
            textAlign: TextAlign.center,
            style: TextStyle(color: PgTokens.colorTextMuted),
          ),
        ),
      ),
    );
  }
}
