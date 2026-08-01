import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/customer_avatar_controller.dart';
import '../../core/controllers/guard_avatar_controller.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/profile_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/media/document_picker.dart';
import '../../core/models/profile.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../auth/widgets/switch_mode_action.dart';
import 'widgets/lang_segmented.dart';

/// Profile + settings: identity header (avatar/name/role/approval), personal-info entry (→ edit),
/// read-only phone (the login identifier), language toggle, and logout. UI per the
/// `Mobile - Guard App.html` / `Mobile - Customer App.html` profile screens.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(profileControllerProvider.notifier);
    // Pre-logout ACTIVE-JOB check (guard-enrolled accounts, regardless of the active mode): if
    // an assignment is still in flight, the dialog warns that live GPS to the customer stops
    // until the guard signs back in — logout stays ALLOWED (the job is server-owned and resumes
    // after the PIN re-login). Best-effort + fail-open: an offline logout must never be blocked
    // by this read, so any error/timeout just skips the warning.
    var warnActiveJob = false;
    final user = ref.read(sessionProvider).user;
    if (user != null && user.isEnrolledIn('guard')) {
      try {
        final jobs = await ref
            .read(guardJobsControllerProvider.future)
            .timeout(const Duration(seconds: 3));
        warnActiveJob = GuardJobsController.active(jobs).isNotEmpty;
      } catch (_) {
        // Fail-open: no warning rather than a blocked logout.
      }
    }
    if (!context.mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      // Design overlay rgba(8,20,15,0.55) has no token — nearest is colorBrand @ 55%.
      barrierColor: PgTokens.colorBrand.withValues(alpha: 0.55),
      builder: (c) => _LogoutDialog(warnActiveJob: warnActiveJob),
    );
    if (yes != true) return;
    // On success the session flips to unauthenticated and the router redirects to auth.
    await notifier.logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(profileControllerProvider);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'โปรไฟล์' : 'Profile',
        subtitle: isThai ? 'โปรไฟล์และการตั้งค่า' : 'Profile & settings',
        showBack: true,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title: isThai ? 'โหลดโปรไฟล์ไม่สำเร็จ' : 'Could not load profile',
            message: e is ApiException ? e.message : null,
            onRetry: () => ref.invalidate(profileControllerProvider),
          ),
          data: (profile) => ListView(
            padding: const EdgeInsets.all(PgTokens.space4),
            children: [
              _Header(profile: profile, isThai: isThai),
              const SizedBox(height: PgTokens.space4),
              _SectionLabel(isThai ? 'ตั้งค่า' : 'Settings'),
              const SizedBox(height: PgTokens.space2),
              // One continuous settings list (design .prow): rows separated by
              // 1px dividers inside a single bordered surface card.
              _SettingsGroup(
                children: [
                  _Tile(
                    icon: Icons.person_outline,
                    title: isThai ? 'ข้อมูลส่วนตัว' : 'Personal info',
                    subtitle: profile.isGuard
                        ? (isThai
                            ? 'เพศ วันเกิด ประสบการณ์'
                            : 'Gender, birthday, experience')
                        : (isThai ? 'ชื่อ ที่อยู่' : 'Name, address'),
                    onTap: () => context.push('/profile/edit'),
                  ),
                  if (profile.isGuard)
                    _Tile(
                      icon: Icons.account_balance_outlined,
                      title: isThai ? 'บัญชีธนาคาร' : 'Bank account',
                      subtitle:
                          '${profile.bankName ?? '—'} · ${profile.accountNumberMasked ?? '—'}',
                      onTap: () => context.push('/profile/edit'),
                    ),
                  if (profile.isGuard)
                    _Tile(
                      icon: Icons.badge_outlined,
                      title: isThai ? 'เอกสารของฉัน' : 'My documents',
                      subtitle: isThai
                          ? 'อัปโหลดเอกสารประจำตัว'
                          : 'Upload your credentials',
                      onTap: () => context.push('/profile/documents'),
                    ),
                  if (profile.isGuard)
                    _Tile(
                      icon: Icons.history,
                      title: isThai ? 'ประวัติงาน' : 'Work history',
                      subtitle: isThai
                          ? 'งานที่เสร็จและยกเลิก'
                          : 'Completed & cancelled jobs',
                      onTap: () => context.push('/guard/history'),
                    ),
                  _Tile(
                    icon: Icons.help_outline,
                    title: isThai ? 'ช่วยเหลือ' : 'Help',
                    subtitle:
                        isThai ? 'คำถามที่พบบ่อย · ติดต่อเรา' : 'FAQ & contact',
                    onTap: () => context.push('/help'),
                  ),
                  // The mode picker (no logout) — a clear, labelled path to role-selection in the
                  // settings, for EVERY authenticated account: dual-role to SWITCH, single-role to
                  // ENROL a second role ("เพิ่มบทบาท"). Shown whenever a user is signed in (the tile
                  // self-hides only when there is no user), so a single-role account always has an
                  // obvious "go to role-select" entry, not just the small header icon.
                  if (ref.watch(sessionProvider.select((s) => s.user != null)))
                    const SwitchModeTile(),
                  _ReadonlyRow(
                    icon: Icons.phone_outlined,
                    label: isThai ? 'เบอร์โทร (ใช้เข้าสู่ระบบ)' : 'Phone',
                    value: profile.phone ?? '—',
                  ),
                  const _LanguageRow(),
                  const _BiometricRow(),
                ],
              ),
              const SizedBox(height: PgTokens.space6),
              OutlinedButton.icon(
                onPressed: () => _logout(context, ref),
                icon: const Icon(Icons.logout, size: 18),
                label: Text(isThai ? 'ออกจากระบบ' : 'Log out'),
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
class _LogoutDialog extends ConsumerWidget {
  const _LogoutDialog({this.warnActiveJob = false});

  /// When the guard has an ACTIVE assignment: swap the body copy for a warning that live GPS to
  /// the customer stops until they sign back in (logout is still allowed — the job resumes on
  /// the PIN re-login).
  final bool warnActiveJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
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
              decoration: BoxDecoration(
                color: warnActiveJob
                    ? PgTokens.colorAmber50
                    : PgTokens.colorDangerBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                  warnActiveJob ? Icons.work_history_outlined : Icons.logout,
                  size: 26,
                  color: warnActiveJob
                      ? PgTokens.colorAmber700
                      : PgTokens.colorDanger),
            ),
            // Design: 18px below the icon circle (non-token design metric).
            const SizedBox(height: 18),
            Text(
              warnActiveJob
                  ? (isThai ? 'มีงานค้างอยู่' : 'You have an active job')
                  : (isThai ? 'ออกจากระบบ?' : 'Log out?'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: PgTokens.space2),
            Text(
              warnActiveJob
                  ? (isThai
                      ? 'คุณมีงานที่กำลังดำเนินอยู่ — ออกจากระบบแล้วตำแหน่ง GPS จะหยุดส่งให้ลูกค้าจนกว่าจะเข้าสู่ระบบด้วย PIN อีกครั้ง งานจะไม่ถูกยกเลิกและกลับมาทำต่อได้'
                      : 'A job is in progress — logging out stops live GPS to the customer until you sign back in with your PIN. The job is not cancelled and you can resume it.')
                  : (isThai
                      ? 'เซสชันจะถูกยกเลิกและล้างโทเคนในเครื่อง คุณต้องเข้าสู่ระบบด้วย PIN อีกครั้ง'
                      : 'Session revoked and local tokens cleared. Sign in with your PIN again.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13.5, color: PgTokens.colorTextMuted),
            ),
            const SizedBox(height: PgTokens.space6),
            PgPrimaryButton(
              label: warnActiveJob
                  ? (isThai ? 'ออกจากระบบต่อ' : 'Log out anyway')
                  : (isThai ? 'ออกจากระบบ' : 'Log out'),
              color: PgTokens.colorDanger,
              onPressed: () => Navigator.pop(context, true),
            ),
            // Design: 10px between the stacked buttons (non-token design metric).
            const SizedBox(height: 10),
            PgPrimaryButton(
              label: isThai ? 'ยกเลิก' : 'Cancel',
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
  const _Header({required this.profile, required this.isThai});

  final UserProfile profile;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Both roles can upload/replace their own profile picture; the editable avatar reads the
        // role-matching controller (guard → /profile/guard/{id}/avatar, customer →
        // /profile/customer/{id}/avatar), falling back to initials before a photo is set / on error.
        _EditableAvatar(initials: profile.initials, isGuard: profile.isGuard),
        const SizedBox(height: PgTokens.space3),
        Text(profile.displayName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              profile.isGuard
                  ? (isThai ? 'เจ้าหน้าที่' : 'Guard')
                  : (isThai ? 'ลูกค้า' : 'Customer'),
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

/// Plain initials avatar (customers, and the guard fallback before an image is set / on load error).
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 37,
      backgroundColor: PgTokens.colorGreen100,
      child: Text(
        initials,
        style: const TextStyle(
            color: PgTokens.colorGreen800,
            fontSize: 26,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The caller's editable avatar (works for BOTH roles): their uploaded profile picture (presigned
/// URL) over an initials fallback, with a camera badge and tap-to-upload (camera/gallery → own-only
/// multipart). A spinner overlays while uploading; the previous image stays visible underneath.
/// Honest: shows initials (never a fake image) until one is uploaded or if the presigned URL fails
/// to load. [isGuard] only selects which own-only controller/endpoint to drive — the guard avatar
/// (`/profile/guard/{id}/avatar`) or the customer avatar (`/profile/customer/{id}/avatar`); the UI
/// is identical.
class _EditableAvatar extends ConsumerWidget {
  const _EditableAvatar({required this.initials, required this.isGuard});

  final String initials;
  final bool isGuard;

  Future<void> _pickAndUpload(
      BuildContext context, WidgetRef ref, bool isThai) async {
    final source = await showModalBottomSheet<DocSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(isThai ? 'ถ่ายรูป' : 'Take photo'),
              onTap: () => Navigator.pop(ctx, DocSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(isThai ? 'เลือกจากคลัง' : 'Choose from gallery'),
              onTap: () => Navigator.pop(ctx, DocSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final path = await ref.read(documentPickerProvider).pick(source);
    if (path == null) return;
    if (!context.mounted) return;
    final err = isGuard
        ? await ref.read(guardAvatarControllerProvider.notifier).upload(path)
        : await ref
            .read(customerAvatarControllerProvider.notifier)
            .upload(path);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = isGuard
        ? ref.watch(guardAvatarControllerProvider)
        : ref.watch(customerAvatarControllerProvider);
    final url = async.valueOrNull;
    final uploading = async.isLoading;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // TAP THE PICTURE = VIEW it full-screen (what a profile picture tap should do). Changing it
        // is the camera badge below — tapping the whole avatar used to jump straight into the
        // upload sheet, so there was no way to just look at the photo you uploaded.
        // With no photo yet there is nothing to view, so the tap falls back to the upload flow.
        GestureDetector(
          onTap: uploading
              ? null
              : () => url != null
                  ? showImageViewer(context, url: url, isThai: isThai)
                  : _pickAndUpload(context, ref, isThai),
          child: ClipOval(
            child: url != null
                ? Image.network(
                    url,
                    width: 74,
                    height: 74,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _InitialsAvatar(initials: initials),
                  )
                : _InitialsAvatar(initials: initials),
          ),
        ),
        if (uploading)
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        // Camera badge (bottom-right) — THE affordance to (re)upload, now the tap target for it
        // (the picture itself opens the viewer). Wrapped so the small badge is comfortably tappable.
        Positioned(
          bottom: -2,
          right: -2,
          child: Semantics(
            button: true,
            label: isThai ? 'เปลี่ยนรูปโปรไฟล์' : 'Change profile picture',
            child: InkResponse(
              onTap:
                  uploading ? null : () => _pickAndUpload(context, ref, isThai),
              radius: 22,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: PgTokens.colorPrimary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_camera,
                    size: 14, color: PgTokens.colorSurface),
              ),
            ),
          ),
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
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
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
    final isThai = locale == AppLocale.th;
    return Padding(
      padding: _rowPadding,
      child: Row(
        children: [
          const _IconTile(icon: Icons.translate),
          const SizedBox(width: PgTokens.space3),
          Expanded(
            child: Text(isThai ? 'ภาษา' : 'Language',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600)),
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

/// Post-onboarding biometric toggle. The ONLY enable point used to be the registration enroll
/// screen and `disable()` had zero callers, so a user who skipped it (or set their PIN via reset)
/// could never turn biometric unlock on, and someone who enabled it could never turn it off
/// (deep-review). Hidden when the device has no enrolled biometric. Enabling re-prompts the OS
/// biometric (its own verification).
class _BiometricRow extends ConsumerStatefulWidget {
  const _BiometricRow();

  @override
  ConsumerState<_BiometricRow> createState() => _BiometricRowState();
}

class _BiometricRowState extends ConsumerState<_BiometricRow> {
  bool _available = false;
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final svc = ref.read(biometricServiceProvider);
    final available = await svc.isAvailable();
    final enabled = await svc.isEnabled();
    if (!mounted) return;
    setState(() {
      _available = available;
      _enabled = enabled;
    });
  }

  Future<void> _toggle(bool want) async {
    if (_busy) return;
    setState(() => _busy = true);
    final svc = ref.read(biometricServiceProvider);
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    if (want) {
      final ok = await svc.enable(
          reason: isThai
              ? 'ยืนยันตัวตนเพื่อเปิดใช้การปลดล็อกด้วยไบโอเมตริก'
              : 'Authenticate to enable biometric unlock');
      if (!mounted) return;
      setState(() {
        _enabled = ok;
        _busy = false;
      });
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isThai
                ? 'เปิดใช้ไม่สำเร็จ — ตรวจสอบไบโอเมตริกในเครื่อง'
                : 'Could not enable — check your device biometrics')));
      }
    } else {
      await svc.disable();
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Padding(
      padding: _rowPadding,
      child: Row(
        children: [
          const _IconTile(icon: Icons.fingerprint),
          const SizedBox(width: PgTokens.space3),
          Expanded(
            child: Text(isThai ? 'ปลดล็อกด้วยไบโอเมตริก' : 'Biometric unlock',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600)),
          ),
          Switch(value: _enabled, onChanged: _busy ? null : _toggle),
        ],
      ),
    );
  }
}
