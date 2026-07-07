import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/auth_controller.dart';
import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/registration_controller.dart';
import '../../../core/controllers/session_controller.dart';
import '../../../core/models/registration.dart';
import '../../../core/providers.dart';
import '../../../widgets/auth_head.dart';
import '../../../widgets/primary_button.dart';

/// Shown after the profile is submitted: the account is registered but PENDING approval (no
/// tokens, can't log in yet). Hi-fi layout: role-tinted hero circle + per-role heading/body +
/// role badge pill, then a flexible spacer and the bottom-pinned "check status" CTA. The
/// persisted (masked) summary still backs the cold-start role detection — it is no longer
/// rendered (the design shows no summary list). "Check status" attempts `loginWithPin` — which
/// succeeds only once the account is approved (then the session flips to authenticated and the
/// router redirects to the dashboard); otherwise it stays pending. There is no editing of a
/// submitted profile (v2).
class RegistrationPendingScreen extends ConsumerStatefulWidget {
  const RegistrationPendingScreen({super.key});

  @override
  ConsumerState<RegistrationPendingScreen> createState() =>
      _RegistrationPendingScreenState();
}

class _RegistrationPendingScreenState
    extends ConsumerState<RegistrationPendingScreen> {
  RegistrationSummary? _summary;

  @override
  void initState() {
    super.initState();
    // Live flow: the summary is on the controller. Cold start (fresh keepAlive controller): load
    // the masked summary persisted to prefs at submit (it carries the role for the hero/badge).
    _summary = ref.read(registrationControllerProvider).submitted;
    if (_summary == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromPrefs());
    }
  }

  Future<void> _loadFromPrefs() async {
    final raw = await ref.read(prefsStoreProvider).getString(kRegSummaryKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = RegistrationSummary.tryFromJson(json);
      if (parsed != null && mounted) setState(() => _summary = parsed);
    } catch (_) {
      // Ignore a corrupt cached summary — the pending state is still valid.
    }
  }

  Future<void> _checkStatus() async {
    final ctrl = ref.read(registrationControllerProvider.notifier);
    final approved = ctrl.canCheckSilently
        ? await ctrl.checkStatus()
        : await _checkWithReenteredPin(ctrl);
    if (!mounted || approved == null) return;
    if (approved) {
      // The login just flipped the session to authenticated — but the router's authenticated
      // branch KEEPS `/auth/pending` in place (a carve-out for the add-role background flow), so it
      // won't auto-redirect a first-role approval off this screen (the user otherwise had to
      // force-close + reopen the app to get in). Navigate explicitly to the SAME destination the
      // router picks for a fresh login (mode picker for multi-role, else the role home).
      final user = ref.read(sessionProvider).user;
      context.go(user?.hasMultipleRoles == true
          ? '/auth/role'
          : (user?.isGuard == true ? '/home/guard' : '/home/customer'));
      return;
    }
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        isThai ? 'ยังรอการอนุมัติอยู่' : 'Still pending approval',
      ),
    ));
  }

  /// Start the "register the OTHER role too" flow: re-verify the account's phone by OTP (a pending
  /// account has no token and the register profile_token is spent), then add the opposite role.
  /// There are exactly two roles, so the target is deterministic (guard↔customer). The captcha →
  /// OTP screens run, then `POST /auth/register/add-role` + the new role's profile form.
  Future<void> _addOtherRole() async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final currentIsGuard = _summary?.role.isGuard ?? false;
    final target =
        currentIsGuard ? RegistrationRole.customer : RegistrationRole.guard;
    final phone = await ref.read(appStoreProvider).readPhone();
    if (!mounted) return;
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isThai
            ? 'ไม่พบเบอร์โทร กรุณาเข้าสู่ระบบใหม่'
            : 'Phone not found — please sign in again'),
      ));
      return;
    }
    ref
        .read(authControllerProvider.notifier)
        .startAddRolePending(phone: phone, targetRoleWire: target.wire);
    context.push('/auth/captcha');
  }

  /// Cold start: the in-memory PIN is gone, so re-enter it to attempt the approved-login.
  Future<bool?> _checkWithReenteredPin(RegistrationController ctrl) async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isThai ? 'ใส่ PIN เพื่อตรวจสอบ' : 'Enter PIN'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '••••••'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(isThai ? 'ตรวจสอบ' : 'Check'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pin == null || pin.length != 6) return null;
    return ctrl.checkStatusWithPin(pin);
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(registrationControllerProvider);
    final isGuard = _summary?.role.isGuard ?? false;

    // No green bar — the pending screen is terminal (no back in the hi-fi) and its hero head
    // is the body AuthHead; dark status-bar icons for the light page.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Hero (design: text-align center, padding 50 30 20).
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 50, 30, 20),
                child: Column(
                  children: [
                    AuthHead(
                      icon: _HeroCircle(isGuard: isGuard),
                      title: isGuard
                          ? (isThai
                              ? 'กำลังตรวจสอบใบสมัคร'
                              : 'Application under review')
                          : (isThai ? 'เกือบเสร็จแล้ว!' : 'Almost there!'),
                      subtitle: isGuard
                          ? (isThai
                              ? 'ทีมงานกำลังตรวจสอบเอกสารของคุณ\n'
                                  'โดยปกติใช้เวลา 1–2 วันทำการ'
                              : 'Our team is verifying your documents.\n'
                                  'This usually takes 1–2 business days.')
                          : (isThai
                              ? 'บัญชีของคุณกำลังรอการยืนยัน\n'
                                  'เราจะแจ้งเตือนทันทีที่พร้อมใช้งาน'
                              : "Your account is awaiting verification.\n"
                                  "We'll notify you the moment it's ready."),
                    ),
                    const SizedBox(height: PgTokens.space4),
                    _RoleBadge(isGuard: isGuard, isThai: isThai),
                  ],
                ),
              ),
              const Spacer(),
              // Footer: primary "check status" + a secondary "register the other role too" so a
              // pending user isn't stuck — they can add the opposite role (both await approval).
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    20, PgTokens.space4, 20, PgTokens.space2),
                child: PgPrimaryButton(
                  label: isThai ? 'ตรวจสอบสถานะ' : 'Check status',
                  busy: state.busy,
                  onPressed: state.busy ? null : _checkStatus,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, PgTokens.space4),
                child: SizedBox(
                  height: 52,
                  child: TextButton(
                    onPressed: state.busy ? null : _addOtherRole,
                    style: TextButton.styleFrom(
                      foregroundColor: PgTokens.colorGreen800,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                        side: const BorderSide(color: PgTokens.colorBorder),
                      ),
                    ),
                    child: Text(
                      isGuard
                          ? (isThai
                              ? 'สมัครเป็นลูกค้าด้วย'
                              : 'Also register as a customer')
                          : (isThai
                              ? 'สมัครเป็นเจ้าหน้าที่ด้วย'
                              : 'Also register as a guard'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
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

/// Design `.ic`: 96px tinted circle — guard = warning-bg + amber-600 clock, customer =
/// amber-100 + amber-700 check (exact tokens since the full-ramp regen).
class _HeroCircle extends StatelessWidget {
  const _HeroCircle({required this.isGuard});

  final bool isGuard;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: isGuard ? PgTokens.colorWarningBg : PgTokens.colorAmber100,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isGuard ? Icons.schedule : Icons.check,
        size: 44,
        color: isGuard ? PgTokens.colorAmber600 : PgTokens.colorAmber700,
      ),
    );
  }
}

/// Design role badge pill: guard = green-900 (brand) on white text + shield; customer =
/// amber-100 with amber-700 text + user icon.
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.isGuard, required this.isThai});

  final bool isGuard;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final fg = isGuard ? Colors.white : PgTokens.colorAmber700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isGuard ? PgTokens.colorBrand : PgTokens.colorAmber100,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isGuard ? Icons.shield_outlined : Icons.person_outline,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 7),
          Text(
            isGuard
                ? (isThai ? 'เจ้าหน้าที่ รปภ.' : 'Security Guard')
                : (isThai ? 'ลูกค้าจ้างงาน' : 'Hirer'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
