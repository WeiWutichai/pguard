import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/providers.dart';
import '../../widgets/auth_head.dart';
import '../../widgets/primary_button.dart';

/// Step 5 (design `Mobile - Auth.html` ⑤): the OPTIONAL "Enable Face ID?" enrolment screen,
/// shown once right after the PIN is set+confirmed and before role selection. Enabling biometric
/// is a convenience fast-path over the PIN gate — never a replacement (the PIN stays the
/// fallback). The screen is only reached when the device actually supports biometrics (the PIN
/// screen checks first); a defensive check here forwards straight to role-select otherwise.
class BiometricEnrollScreen extends ConsumerStatefulWidget {
  const BiometricEnrollScreen({super.key});

  @override
  ConsumerState<BiometricEnrollScreen> createState() =>
      _BiometricEnrollScreenState();
}

class _BiometricEnrollScreenState extends ConsumerState<BiometricEnrollScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Defensive: if biometrics aren't actually available (e.g. unenrolled mid-flow), don't strand
    // the user on a dead screen — skip straight to role-select.
    Future.microtask(() async {
      final available = await ref.read(biometricServiceProvider).isAvailable();
      if (!mounted || available) return;
      context.pushReplacement('/auth/role');
    });
  }

  void _continue() {
    if (!mounted) return;
    context.push('/auth/role');
  }

  Future<void> _enable() async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    setState(() => _busy = true);
    final ok = await ref.read(biometricServiceProvider).enable(
          reason: isThai
              ? 'ยืนยันตัวตนเพื่อเปิดใช้การปลดล็อกด้วยไบโอเมตริก'
              : 'Authenticate to enable biometric unlock',
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _continue();
    } else {
      // The button used to do NOTHING on failure (e.g. an Android sensor with no enrolled
      // fingerprint → the plugin throws NotEnrolled, swallowed to false) — a dead button with zero
      // feedback (deep-review). Tell the user why + point them to set one up in Settings.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isThai
            ? 'ยังไม่ได้ตั้งค่าลายนิ้วมือ/ใบหน้าในเครื่อง หรือการยืนยันไม่สำเร็จ — ตั้งค่าในการตั้งค่าเครื่องก่อน หรือกด "ข้ามไปก่อน"'
            : 'No fingerprint/face is set up on this device, or authentication failed — add one in Settings, or tap "Skip for now"'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
          child: Column(
            children: [
              const SizedBox(height: 60),
              AuthHead(
                icon: const AuthHeadIconTile(icon: Icons.fingerprint),
                title: isThai ? 'เปิดใช้ไบโอเมตริก?' : 'Enable biometric unlock?',
                subtitle: isThai
                    ? 'เข้าแอปได้เร็วและปลอดภัยขึ้น\nโดยไม่ต้องพิมพ์ PIN ทุกครั้ง'
                    : 'Sign in faster and more securely\nwithout typing your PIN every time',
              ),
              const Spacer(),
              PgPrimaryButton(
                label: isThai ? 'เปิดใช้ไบโอเมตริก' : 'Enable biometrics',
                busy: _busy,
                onPressed: _busy ? null : _enable,
              ),
              const SizedBox(height: PgTokens.space2),
              PgGhostButton(
                label: isThai ? 'ข้ามไปก่อน' : 'Skip for now',
                onPressed: _busy ? null : _continue,
              ),
              const SizedBox(height: PgTokens.space4),
            ],
          ),
        ),
      ),
    );
  }
}
