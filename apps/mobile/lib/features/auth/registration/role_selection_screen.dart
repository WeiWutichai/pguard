import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/registration_controller.dart';
import '../../../core/models/registration.dart';
import '../../profile/widgets/lang_segmented.dart';

/// Step 4 (after PIN): choose `guard` or `customer`. The tap registers the account
/// (`POST /auth/register`, role-at-register) — on 202 we go to the matching profile form; a 409
/// ("already registered") logs the returning user in and the router redirects to their dashboard.
///
/// Design (stitch role-chooser): a top-right TH|EN toggle, a hero illustration (guard + protected
/// home), the centered "คุณคือใคร?" headline + subtitle, then two `.role-card`s — Guard FIRST with
/// a green-900 shield tile ("เจ้าหน้าที่ รปภ."), then "จ้าง รปภ" with an amber person-search tile —
/// each a border-only card with a 56×56 icon tile + trailing chevron, and a copyright footer.
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space3),
              // Pre-login language choice, top-right (design `.seg-sm`).
              Align(
                alignment: Alignment.centerRight,
                child: LangSegmented(
                  value: ref.watch(localeControllerProvider),
                  onChanged: (l) =>
                      ref.read(localeControllerProvider.notifier).setLocale(l),
                ),
              ),
              const SizedBox(height: PgTokens.space2),
              // Hero illustration — a guard presenting the app over a protected home.
              Image.asset('assets/images/role_hero.png',
                  height: 200, fit: BoxFit.contain),
              const SizedBox(height: PgTokens.space5),
              Text(
                isThai ? 'คุณคือใคร?' : 'Who are you?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
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
                    ? 'สำหรับเจ้าหน้าที่เพื่อเข้าใช้งานระบบ'
                    : 'For guards to access the system',
                enabled: !state.busy,
                onTap: () => choose(RegistrationRole.guard),
              ),
              const SizedBox(height: 14),
              // Customer second — "hire a guard" (amber person-search tile).
              _RoleCard(
                icon: Icons.person_search_outlined,
                iconBg: PgTokens.colorAmber100,
                iconFg: PgTokens.colorAmber700,
                title: isThai ? 'จ้าง รปภ' : 'Hire a Guard',
                desc: isThai
                    ? 'จ้างเจ้าหน้าที่รักษาความปลอดภัยระดับมืออาชีพ'
                    : 'Hire professional security guards',
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
              const SizedBox(height: PgTokens.space7),
              const Text(
                '© 2023 Security Platform System',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 12, color: PgTokens.colorTextFaint),
              ),
              const SizedBox(height: PgTokens.space5),
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
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  color: PgTokens.colorTextFaint, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
