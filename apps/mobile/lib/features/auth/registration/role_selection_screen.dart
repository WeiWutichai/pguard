import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/registration_controller.dart';
import '../../../core/models/registration.dart';
import '../../../widgets/pg_auth_back_bar.dart';

/// Step 4 (after PIN): choose `guard` or `customer`. The tap registers the account
/// (`POST /auth/register`, role-at-register) — on 202 we go to the matching profile form; a 409
/// ("already registered") logs the returning user in and the router redirects to their dashboard.
///
/// Hi-fi: Mobile - Auth.html screen 6 — a centered "คุณคือใคร?" hero, then two `.role-card`s
/// (Guard FIRST with a green-900 shield tile, then Customer with an amber user tile), each a
/// border-only card with a 56×56 colored icon tile and no trailing chevron.
class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
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
      // Registration has no green bar in the hi-fi (bare back chevron); the body carries the hero.
      appBar: const PgAuthBackBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space7),
              // Centered hero (.auth-head).
              Text(
                isThai ? 'คุณคือใคร?' : 'Who are you?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: PgTokens.colorTextStrong,
                ),
              ),
              const SizedBox(height: PgTokens.space2),
              Text(
                isThai ? 'เลือกบทบาทเพื่อเริ่มต้น' : 'Pick a role to continue',
                textAlign: TextAlign.center,
                style: const TextStyle(color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space6),
              // Guard FIRST (green-900 shield tile).
              _RoleCard(
                icon: Icons.shield_outlined,
                iconBg: PgTokens.colorGreen900,
                iconFg: Colors.white,
                title: isThai ? 'เจ้าหน้าที่ รปภ.' : 'Security Guard',
                desc: isThai
                    ? 'รับงาน ส่งรายงาน ดูรายได้'
                    : 'Accept jobs, report, earn',
                enabled: !state.busy,
                onTap: () => choose(RegistrationRole.guard),
              ),
              const SizedBox(height: 14),
              // Customer second (amber user tile).
              _RoleCard(
                icon: Icons.person_outline,
                iconBg: PgTokens.colorAmber100,
                iconFg: PgTokens.colorAmber700,
                title: isThai ? 'ลูกค้าจ้างงาน' : 'Hirer / Customer',
                desc:
                    isThai ? 'จองและติดตามเจ้าหน้าที่' : 'Book & track guards',
                enabled: !state.busy,
                onTap: () => choose(RegistrationRole.customer),
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

/// `.role-card`: a border-only card (1.5px, radius 20, padding 22, gap 16) with a 56×56 colored
/// icon tile (radius 16) + title (.rt 18/w600) and description (.rd 13/muted). No chevron.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.desc,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String desc;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: PgTokens.colorBorder, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 28, color: iconFg),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: PgTokens.colorTextStrong)),
                    const SizedBox(height: 3),
                    Text(desc,
                        style: const TextStyle(
                            color: PgTokens.colorTextMuted,
                            fontSize: 13,
                            height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
