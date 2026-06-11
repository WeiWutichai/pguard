import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/profile_controller.dart';
import '../../core/models/profile.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets/lang_segmented.dart';

/// Profile + settings: identity header (avatar/name/role/approval), personal-info entry (→ edit),
/// read-only phone (the login identifier), language toggle, and logout. UI per the
/// `Mobile - Guard App.html` / `Mobile - Customer App.html` profile screens.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(profileControllerProvider.notifier);
    final yes = await showDialog<bool>(
      context: context,
      // Design overlay rgba(8,20,15,0.55) has no token — nearest is colorBrand @ 55%.
      barrierColor: PgTokens.colorBrand.withValues(alpha: 0.55),
      builder: (c) => const _LogoutDialog(),
    );
    if (yes != true) return;
    // On success the session flips to unauthenticated and the router redirects to auth.
    await notifier.logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileControllerProvider);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: const PGuardHeader(
        title: 'โปรไฟล์',
        subtitle: 'Profile & settings',
        showBack: true,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title: 'โหลดโปรไฟล์ไม่สำเร็จ / Could not load profile',
            message: e is ApiException ? e.message : null,
            onRetry: () => ref.invalidate(profileControllerProvider),
          ),
          data: (profile) => ListView(
            padding: const EdgeInsets.all(PgTokens.space4),
            children: [
              _Header(profile: profile),
              const SizedBox(height: PgTokens.space4),
              const _SectionLabel('ตั้งค่า / Settings'),
              const SizedBox(height: PgTokens.space2),
              // One continuous settings list (design .prow): rows separated by
              // 1px dividers inside a single bordered surface card.
              _SettingsGroup(
                children: [
                  _Tile(
                    icon: Icons.person_outline,
                    title: 'ข้อมูลส่วนตัว / Personal info',
                    subtitle: profile.isGuard
                        ? 'เพศ วันเกิด ประสบการณ์'
                        : 'ชื่อ ที่อยู่',
                    onTap: () => context.push('/profile/edit'),
                  ),
                  if (profile.isGuard)
                    _Tile(
                      icon: Icons.account_balance_outlined,
                      title: 'บัญชีธนาคาร / Bank account',
                      subtitle:
                          '${profile.bankName ?? '—'} · ${profile.accountNumberMasked ?? '—'}',
                      onTap: () => context.push('/profile/edit'),
                    ),
                  _ReadonlyRow(
                    icon: Icons.phone_outlined,
                    label: 'เบอร์โทร (ใช้เข้าสู่ระบบ) / Phone',
                    value: profile.phone ?? '—',
                  ),
                  const _LanguageRow(),
                ],
              ),
              const SizedBox(height: PgTokens.space6),
              OutlinedButton.icon(
                onPressed: () => _logout(context, ref),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('ออกจากระบบ / Log out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PgTokens.colorDanger,
                  side: const BorderSide(color: PgTokens.colorDanger),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PgTokens.radiusMd),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The designed logout confirmation (Mobile - System.html dialog): danger icon circle,
/// centered title/description, then stacked full-width danger CTA + sunken cancel.
/// Pops `true` to confirm — the logout call itself stays in [ProfileScreen._logout].
class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: PgTokens.colorSurface,
      shape: RoundedRectangleBorder(
        // Design 22px corners — nearest token is radius2xl (18).
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      ),
      child: Padding(
        // Design: 26px 24px dialog padding (non-token design metric).
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: PgTokens.colorDangerBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout,
                  size: 26, color: PgTokens.colorDanger),
            ),
            // Design: 18px below the icon circle (non-token design metric).
            const SizedBox(height: 18),
            const Text(
              'ออกจากระบบ? / Log out?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: PgTokens.space2),
            const Text(
              'เซสชันจะถูกยกเลิกและล้างโทเคนในเครื่อง คุณต้องเข้าสู่ระบบด้วย PIN อีกครั้ง\n'
              'Session revoked and local tokens cleared. Sign in with your PIN again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: PgTokens.colorTextMuted),
            ),
            const SizedBox(height: PgTokens.space6),
            PgPrimaryButton(
              label: 'ออกจากระบบ / Log out',
              color: PgTokens.colorDanger,
              onPressed: () => Navigator.pop(context, true),
            ),
            // Design: 10px between the stacked buttons (non-token design metric).
            const SizedBox(height: 10),
            PgPrimaryButton(
              label: 'ยกเลิก / Cancel',
              color: PgTokens.colorSunken,
              foreground: PgTokens.colorText,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 37,
          backgroundColor: PgTokens.colorGreen100,
          child: Text(
            profile.initials,
            style: const TextStyle(
                color: PgTokens.colorGreen800,
                fontSize: 26,
                fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: PgTokens.space3),
        Text(profile.displayName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              profile.isGuard ? 'เจ้าหน้าที่ · Guard' : 'ลูกค้า · Customer',
              style: const TextStyle(
                  fontSize: 12.5, color: PgTokens.colorTextMuted),
            ),
            if (profile.isGuard && profile.approvalStatus != null) ...[
              const SizedBox(width: PgTokens.space2),
              _ApprovalBadge(status: profile.approvalStatus!),
            ],
          ],
        ),
      ],
    );
  }
}

class _ApprovalBadge extends StatelessWidget {
  const _ApprovalBadge({required this.status});

  final ApprovalStatus status;

  @override
  Widget build(BuildContext context) {
    final (String label, Color fg, Color bg) = switch (status) {
      ApprovalStatus.approved => (
          'ยืนยันแล้ว',
          PgTokens.colorSuccess,
          PgTokens.colorSuccessBg
        ),
      ApprovalStatus.pending => (
          'รออนุมัติ',
          PgTokens.colorAmber700,
          PgTokens.colorWarningBg
        ),
      ApprovalStatus.rejected => (
          'ถูกปฏิเสธ',
          PgTokens.colorDanger,
          PgTokens.colorDangerBg
        ),
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: PgTokens.space2, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: PgTokens.colorTextMuted));
}

/// Design .prow group: one bordered surface card; every row except the last
/// gets a 1px bottom divider. Rows carry their own 16h/14v padding.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Material(
        color: PgTokens.colorSurface,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++)
              i == children.length - 1
                  ? children[i]
                  : Container(
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: PgTokens.colorBorder)),
                      ),
                      child: children[i],
                    ),
          ],
        ),
      ),
    );
  }
}

/// Row padding per design .prow: `padding: 14px 16px`.
const EdgeInsets _rowPadding =
    EdgeInsets.symmetric(horizontal: PgTokens.space4, vertical: 14);

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: _rowPadding,
        child: Row(
          children: [
            _IconTile(icon: icon),
            const SizedBox(width: PgTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Text(subtitle,
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

class _ReadonlyRow extends StatelessWidget {
  const _ReadonlyRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _rowPadding,
      child: Row(
        children: [
          _IconTile(icon: icon),
          const SizedBox(width: PgTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11.5, color: PgTokens.colorTextMuted)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Icon(Icons.lock_outline,
              size: 16, color: PgTokens.colorTextFaint),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: PgTokens.colorSunken,
          borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        ),
        child: Icon(icon, size: 20, color: PgTokens.colorTextMuted),
      );
}

class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    return Padding(
      padding: _rowPadding,
      child: Row(
        children: [
          const _IconTile(icon: Icons.translate),
          const SizedBox(width: PgTokens.space3),
          const Expanded(
            child: Text('ภาษา / Language',
                style:
                    TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          ),
          LangSegmented(
            value: locale,
            onChanged: (l) =>
                ref.read(localeControllerProvider.notifier).setLocale(l),
          ),
        ],
      ),
    );
  }
}
