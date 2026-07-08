import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/profile_controller.dart';
import '../../../core/controllers/session_controller.dart';

/// A header "switch mode / back to role-select" action (CLAUDE.md: shared widget, no copy-paste).
/// Opens the mode picker (`/auth/role`) WITHOUT logging out — the router lets an authenticated user
/// stay on it. Shown for EVERY authenticated user: a multi-role account switches between modes, a
/// SINGLE-role account uses it to ENROL the second role (the only path to "one phone, two roles" —
/// hiding it for single-role was a catch-22 that made adding a 2nd role unreachable).
class SwitchModeAction extends ConsumerWidget {
  const SwitchModeAction({super.key, this.light = false});

  /// White glyph for the brand-green header (homes) vs dark for a light surface.
  final bool light;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final user = ref.watch(sessionProvider.select((s) => s.user));
    if (user == null) return const SizedBox.shrink();
    final multiRole = user.hasMultipleRoles;
    return IconButton(
      icon: Icon(multiRole ? Icons.swap_horiz : Icons.add_circle_outline,
          color: light ? PgTokens.colorTextStrong : Colors.white, size: 22),
      tooltip: isThai
          ? (multiRole ? 'สลับโหมด' : 'เพิ่มบทบาท')
          : (multiRole ? 'Switch mode' : 'Add role'),
      // push (not go) so the picker sits over the home; the picker's own close/back returns here.
      // Invalidate the (home-cached) profile FIRST so the picker re-fetches /auth/me — otherwise the
      // enrolled/pending badges + the A3 load-gate render against a STALE role set (a role submitted
      // or approved since the home mounted wouldn't show).
      onPressed: () {
        ref.invalidate(profileControllerProvider);
        context.push('/auth/role');
      },
    );
  }
}

/// A settings-list row variant of the switch-mode affordance, for the profile screen. Shown for
/// every authenticated user — multi-role to switch, single-role to ENROL the second role. Tapping
/// opens the mode picker.
class SwitchModeTile extends ConsumerWidget {
  const SwitchModeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final user = ref.watch(sessionProvider.select((s) => s.user));
    if (user == null) return const SizedBox.shrink();
    final multiRole = user.hasMultipleRoles;
    return InkWell(
      // Refresh the (home-cached) profile so the picker shows a fresh enrolled/pending role set.
      onTap: () {
        ref.invalidate(profileControllerProvider);
        context.push('/auth/role');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: PgTokens.space4, vertical: 14),
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
                  Text(
                      isThai
                          ? (multiRole ? 'สลับโหมด' : 'เพิ่มบทบาท')
                          : (multiRole ? 'Switch mode' : 'Add role'),
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Text(
                      isThai
                          ? (multiRole
                              ? 'เจ้าหน้าที่ · ลูกค้า'
                              : 'ใช้ได้ทั้งเจ้าหน้าที่และลูกค้าในเบอร์เดียว')
                          : (multiRole
                              ? 'Guard · Customer'
                              : 'Use both roles on one number'),
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
