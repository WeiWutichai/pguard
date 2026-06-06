import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/profile_controller.dart';
import '../../core/models/profile.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pguard_header.dart';
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
      builder: (c) => AlertDialog(
        title: const Text('ออกจากระบบ? / Log out?'),
        content: const Text(
            'เซสชันจะถูกยกเลิกและล้างโทเคนในเครื่อง — ต้องเข้าสู่ระบบด้วย PIN อีกครั้ง\n'
            'Your session is revoked and local tokens cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: PgTokens.colorDanger),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
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
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(PgTokens.space6),
              child: Text(
                e is ApiException
                    ? e.message
                    : 'โหลดโปรไฟล์ไม่สำเร็จ / Could not load profile',
                textAlign: TextAlign.center,
                style: const TextStyle(color: PgTokens.colorTextMuted),
              ),
            ),
          ),
          data: (profile) => ListView(
            padding: const EdgeInsets.all(PgTokens.space4),
            children: [
              _Header(profile: profile),
              const SizedBox(height: PgTokens.space4),
              _Tile(
                icon: Icons.person_outline,
                title: 'ข้อมูลส่วนตัว / Personal info',
                subtitle: profile.isGuard
                    ? 'เพศ วันเกิด ประสบการณ์ บัญชีธนาคาร'
                    : 'ชื่อ ที่อยู่',
                onTap: () => context.push('/profile/edit'),
              ),
              _ReadonlyRow(
                icon: Icons.phone_outlined,
                label: 'เบอร์โทร (ใช้เข้าสู่ระบบ) / Phone',
                value: profile.phone ?? '—',
              ),
              const SizedBox(height: PgTokens.space4),
              const _SectionLabel('ตั้งค่า / Settings'),
              const SizedBox(height: PgTokens.space2),
              const _LanguageRow(),
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
                fontSize: 24,
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
    return Material(
      color: PgTokens.colorSurface,
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(PgTokens.space3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            border: Border.all(color: PgTokens.colorBorder),
          ),
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
    return Container(
      margin: const EdgeInsets.only(top: PgTokens.space3),
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
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
          color: PgTokens.colorGreen50,
          borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        ),
        child: Icon(icon, size: 20, color: PgTokens.colorGreen800),
      );
}

class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    return Container(
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        border: Border.all(color: PgTokens.colorBorder),
      ),
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
