import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/session_controller.dart';

/// A header "switch mode / back to role-select" action (CLAUDE.md: shared widget, no copy-paste).
/// Opens the mode picker (`/auth/role`) WITHOUT logging out — the router lets an authenticated user
/// stay on it. Only rendered when the account holds >1 role (a single-role user has nothing to
/// switch to), so it's a no-op affordance otherwise.
class SwitchModeAction extends ConsumerWidget {
  const SwitchModeAction({super.key, this.light = false});

  /// White glyph for the brand-green header (homes) vs dark for a light surface.
  final bool light;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final multiRole = ref.watch(
        sessionProvider.select((s) => s.user?.hasMultipleRoles ?? false));
    if (!multiRole) return const SizedBox.shrink();
    return IconButton(
      icon: Icon(Icons.swap_horiz,
          color: light ? PgTokens.colorTextStrong : Colors.white, size: 22),
      tooltip: isThai ? 'สลับโหมด' : 'Switch mode',
      // push (not go) so the picker sits over the home; the picker's own close/back returns here.
      onPressed: () => context.push('/auth/role'),
    );
  }
}

/// A settings-list row variant of the switch-mode affordance, for the profile screen. Self-hides
/// when the account is single-role (returns an empty box). Tapping opens the mode picker.
class SwitchModeTile extends ConsumerWidget {
  const SwitchModeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final multiRole = ref.watch(
        sessionProvider.select((s) => s.user?.hasMultipleRoles ?? false));
    if (!multiRole) return const SizedBox.shrink();
    return InkWell(
      onTap: () => context.push('/auth/role'),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: PgTokens.space4, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: PgTokens.colorSunken,
                borderRadius: BorderRadius.circular(PgTokens.radiusLg),
              ),
              child: const Icon(Icons.swap_horiz,
                  size: 20, color: PgTokens.colorTextMuted),
            ),
            const SizedBox(width: PgTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isThai ? 'สลับโหมด' : 'Switch mode',
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Text(
                      isThai
                          ? 'เจ้าหน้าที่ · ลูกค้า'
                          : 'Guard · Customer',
                      style: const TextStyle(
                          fontSize: 11.5, color: PgTokens.colorTextMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: PgTokens.colorTextFaint),
          ],
        ),
      ),
    );
  }
}
