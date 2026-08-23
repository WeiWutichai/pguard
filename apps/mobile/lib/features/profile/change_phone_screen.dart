import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../widgets/auth_head.dart';
import '../../widgets/pg_auth_back_bar.dart';
import '../../widgets/primary_button.dart';

/// Step 1 of the signed-in CHANGE-LOGIN-PHONE flow: enter the NEW number. Validates locally, then
/// starts a `phone_change` OTP run ([AuthController.startPhoneChange]) and hands off to the SAME
/// captcha → OTP screens (reused under the authenticated `/profile/phone/*` routes). Nothing is
/// changed until the OTP is verified AND the current PIN is confirmed (`PATCH /auth/phone`).
class ChangePhoneNumberScreen extends ConsumerStatefulWidget {
  const ChangePhoneNumberScreen({super.key});

  @override
  ConsumerState<ChangePhoneNumberScreen> createState() =>
      _ChangePhoneNumberScreenState();
}

class _ChangePhoneNumberScreenState
    extends ConsumerState<ChangePhoneNumberScreen> {
  final TextEditingController _phone = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _continue() {
    final normalized = AuthController.normalizeThaiPhone(_phone.text);
    if (normalized == null) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    // Fresh `phone_change` run with the NEW number; then run the reused captcha → OTP steps.
    ref.read(authControllerProvider.notifier).startPhoneChange(normalized);
    context.push('/profile/phone/captcha');
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Scaffold(
      appBar: const PgAuthBackBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space4),
              AuthHead(
                title: isThai ? 'เปลี่ยนเบอร์โทร' : 'Change phone number',
                subtitle: isThai
                    ? 'กรอกเบอร์ใหม่ เราจะส่งรหัส OTP ไปยืนยัน'
                    : "Enter the new number — we'll send an OTP to verify it",
              ),
              const SizedBox(height: PgTokens.space6),
              TextField(
                controller: _phone,
                autofocus: true,
                keyboardType: TextInputType.phone,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'IBMPlexMono',
                    letterSpacing: 1.2),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                onChanged: (_) {
                  if (_invalid) setState(() => _invalid = false);
                },
                onSubmitted: (_) => _continue(),
                decoration: const InputDecoration(
                  hintText: '81 234 5678',
                  prefixIcon: _PhonePrefix(),
                  prefixIconConstraints:
                      BoxConstraints(minWidth: 0, minHeight: 0),
                ),
              ),
              const SizedBox(height: PgTokens.space4),
              if (_invalid)
                Padding(
                  padding: const EdgeInsets.only(bottom: PgTokens.space3),
                  child: Text(
                    isThai ? 'เบอร์โทรไม่ถูกต้อง' : 'Invalid phone number',
                    style: const TextStyle(color: PgTokens.colorDanger),
                  ),
                ),
              PgPrimaryButton(
                label: isThai ? 'ถัดไป' : 'Next',
                onPressed: _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step 3 (final) of the change-phone flow: confirm the CURRENT PIN as a step-up, then call
/// `PATCH /auth/phone` ([AuthController.changePhone]). On success every session is force-revoked
/// server-side, so the controller drops the session to returning-login on the NEW number and the
/// router lands on the PIN-login screen. On failure (wrong PIN → 401, or the number is taken →
/// `PHONE_TAKEN`) the localized error is shown inline.
class ChangePhoneConfirmScreen extends ConsumerStatefulWidget {
  const ChangePhoneConfirmScreen({super.key});

  @override
  ConsumerState<ChangePhoneConfirmScreen> createState() =>
      _ChangePhoneConfirmScreenState();
}

class _ChangePhoneConfirmScreenState
    extends ConsumerState<ChangePhoneConfirmScreen> {
  final TextEditingController _pin = TextEditingController();
  // Re-entrancy latch: covers the whole submit so a double-tap / keyboard-Go can't fire twice.
  bool _submitting = false;
  String? _err;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_pin.text.trim().length < 6) {
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      setState(
          () => _err = isThai ? 'กรอก PIN 6 หลัก' : 'Enter your 6-digit PIN');
      return;
    }
    setState(() {
      _submitting = true;
      _err = null;
    });
    final err = await ref
        .read(authControllerProvider.notifier)
        .changePhone(currentPin: _pin.text.trim());
    if (!mounted) return;
    if (err == null) {
      // Success: the session flipped to returning-login on the NEW number; the router redirect
      // moves us to /login/pin. Surface a brief confirmation on the way out.
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isThai
            ? 'เปลี่ยนเบอร์สำเร็จ กรุณาเข้าสู่ระบบด้วยเบอร์ใหม่'
            : 'Phone changed — please sign in with the new number'),
      ));
    } else {
      setState(() {
        _submitting = false;
        _err = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final newPhone = ref.watch(authControllerProvider).phone;
    return Scaffold(
      appBar: const PgAuthBackBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space4),
              AuthHead(
                title: isThai ? 'ยืนยันด้วย PIN' : 'Confirm with your PIN',
                subtitle: isThai
                    ? 'กรอก PIN ปัจจุบันเพื่อเปลี่ยนเบอร์เป็น +66 ${AuthController.significantPhone(newPhone)}'
                    : 'Enter your current PIN to change the number to +66 ${AuthController.significantPhone(newPhone)}',
              ),
              const SizedBox(height: PgTokens.space6),
              TextField(
                controller: _pin,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 8),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  hintStyle: TextStyle(letterSpacing: 8),
                ),
              ),
              const SizedBox(height: PgTokens.space4),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: PgTokens.space3),
                  child: Text(
                    _err!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: PgTokens.colorDanger),
                  ),
                ),
              PgPrimaryButton(
                label: isThai ? 'เปลี่ยนเบอร์' : 'Change number',
                busy: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The '🇹🇭 +66' phone prefix (mirrors the phone-entry screen's, kept local to this flow).
class _PhonePrefix extends StatelessWidget {
  const _PhonePrefix();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.only(
          left: PgTokens.space4,
          right: 10,
          top: PgTokens.space1,
          bottom: PgTokens.space1),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: PgTokens.colorBorder)),
      ),
      child: const Text(
        '🇹🇭 +66',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: PgTokens.colorTextMuted,
        ),
      ),
    );
  }
}
