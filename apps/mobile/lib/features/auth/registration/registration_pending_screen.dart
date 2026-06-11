import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/registration_controller.dart';
import '../../../core/models/registration.dart';
import '../../../core/providers.dart';
import '../../../widgets/auth_head.dart';
import '../../../widgets/pguard_header.dart';
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
    // approved == true → session is now authenticated; the router redirects automatically.
    if (!approved) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ยังรอการอนุมัติอยู่ / Still pending approval'),
      ));
    }
  }

  /// Cold start: the in-memory PIN is gone, so re-enter it to attempt the approved-login.
  Future<bool?> _checkWithReenteredPin(RegistrationController ctrl) async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ใส่ PIN เพื่อตรวจสอบ / Enter PIN'),
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
            child: const Text('ยกเลิก / Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('ตรวจสอบ / Check'),
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
    final state = ref.watch(registrationControllerProvider);
    final isGuard = _summary?.role.isGuard ?? false;

    return Scaffold(
      appBar: const PGuardHeader(
        title: 'รอการอนุมัติ',
        subtitle: 'Pending approval',
      ),
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
                        ? 'กำลังตรวจสอบใบสมัคร / Application under review'
                        : 'เกือบเสร็จแล้ว! / Almost there!',
                    subtitle: isGuard
                        ? 'ทีมงานกำลังตรวจสอบเอกสารของคุณ\n'
                            'โดยปกติใช้เวลา 1–2 วันทำการ / '
                            'Our team is verifying your documents.\n'
                            'This usually takes 1–2 business days.'
                        : 'บัญชีของคุณกำลังรอการยืนยัน\n'
                            'เราจะแจ้งเตือนทันทีที่พร้อมใช้งาน / '
                            "Your account is awaiting verification.\n"
                            "We'll notify you the moment it's ready.",
                  ),
                  const SizedBox(height: PgTokens.space4),
                  _RoleBadge(isGuard: isGuard),
                ],
              ),
            ),
            const Spacer(),
            // Footer: CTA pinned above the home indicator.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  20, PgTokens.space4, 20, PgTokens.space4),
              child: PgPrimaryButton(
                label: 'ตรวจสอบสถานะ / Check status',
                busy: state.busy,
                onPressed: state.busy ? null : _checkStatus,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Design `.ic`: 96px tinted circle — guard = warning-bg + clock, customer = amber-100 + check
/// (both icons in amber-700, the nearest token to the design's amber-600/700 pair).
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
        color: PgTokens.colorAmber700,
      ),
    );
  }
}

/// Design role badge pill: guard = green-900 (brand) on white text + shield; customer =
/// amber-100 with amber-700 text + user icon.
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.isGuard});

  final bool isGuard;

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
                ? 'เจ้าหน้าที่ รปภ. / Security Guard'
                : 'ลูกค้าจ้างงาน / Hirer',
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
