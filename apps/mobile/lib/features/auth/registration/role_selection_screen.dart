import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/registration_controller.dart';
import '../../../core/models/registration.dart';
import '../../../widgets/pg_auth_back_bar.dart';

/// Step 4 (after PIN): choose `customer` or `guard`. The tap registers the account
/// (`POST /auth/register`, role-at-register) — on 202 we go to the matching profile form; a 409
/// ("already registered") logs the returning user in and the router redirects to their dashboard.
class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(registrationControllerProvider);
    final ctrl = ref.read(registrationControllerProvider.notifier);

    Future<void> choose(RegistrationRole role) async {
      ctrl.selectRole(role);
      final outcome = await ctrl.register();
      if (!context.mounted) return;
      if (outcome == RegisterOutcome.needsProfile) {
        context.push(
            role.isGuard ? '/auth/register/guard' : '/auth/register/customer');
      }
      // loggedIn → the session is authenticated; the router redirects to the dashboard.
      // error → state.error is rendered below; the user can retry.
    }

    return Scaffold(
      // Registration screens have no green bar in the hi-fi (Mobile - Registration.html uses a
      // bare back chevron); the body already carries the "คุณต้องการใช้งานแบบไหน?" heading.
      appBar: const PgAuthBackBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space2),
              const Text(
                'คุณต้องการใช้งานแบบไหน?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: PgTokens.space2),
              const Text(
                'เลือกได้ครั้งเดียวตอนสมัคร · Chosen once at registration',
                style: TextStyle(color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space6),
              _RoleCard(
                icon: Icons.person_outline,
                titleTh: 'ลูกค้า',
                titleEn: 'Customer',
                descic: 'จองเจ้าหน้าที่รักษาความปลอดภัย · Book guards',
                enabled: !state.busy,
                onTap: () => choose(RegistrationRole.customer),
              ),
              const SizedBox(height: PgTokens.space4),
              _RoleCard(
                icon: Icons.shield_outlined,
                titleTh: 'เจ้าหน้าที่ รปภ.',
                titleEn: 'Security guard',
                descic:
                    'รับงาน · ต้องผ่านการอนุมัติ · Accept jobs (approval required)',
                enabled: !state.busy,
                onTap: () => choose(RegistrationRole.guard),
              ),
              const SizedBox(height: PgTokens.space6),
              if (state.busy)
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (state.error != null && !state.busy)
                Text(
                  state.error!,
                  style: const TextStyle(color: PgTokens.colorDanger),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.titleTh,
    required this.titleEn,
    required this.descic,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String titleTh;
  final String titleEn;
  final String descic;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        child: Container(
          padding: const EdgeInsets.all(PgTokens.space4),
          decoration: BoxDecoration(
            color: PgTokens.colorSunken,
            borderRadius: BorderRadius.circular(PgTokens.radiusXl),
            border: Border.all(color: PgTokens.colorBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 36, color: PgTokens.colorPrimary),
              const SizedBox(width: PgTokens.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$titleTh · $titleEn',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: PgTokens.space1),
                    Text(descic,
                        style: const TextStyle(
                            color: PgTokens.colorTextMuted, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: PgTokens.colorTextMuted),
            ],
          ),
        ),
      ),
    );
  }
}
