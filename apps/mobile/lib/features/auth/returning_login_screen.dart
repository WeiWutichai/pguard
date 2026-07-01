import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/providers.dart';
import '../../widgets/pin_dots.dart';
import '../../widgets/pin_keypad.dart';
import '../../widgets/primary_button.dart';

/// Returning-user PIN LOGIN ([SessionStatus.returning]): the device REMEMBERS the account (the
/// login phone + a local PIN) but holds NO tokens — after a normal logout, or an unrecoverable
/// 401. The user gets back in by entering their PIN: `POST /auth/login` mints a fresh token pair —
/// no OTP, no re-setting a PIN. On success the session flips to authenticated and the router lands
/// on the dashboard (or the mode picker for a dual-role account), which is also what makes the
/// post-re-login role selection work. Distinct from [PinLockScreen] (offline unlock of an existing
/// session) — here the PIN is verified by the SERVER, which owns the login rate-limit.
///
/// "ลืมรหัส PIN" resets the PIN via OTP; "เข้าด้วยบัญชีอื่น" forgets the device and starts fresh
/// at the OTP flow.
class ReturningLoginScreen extends ConsumerStatefulWidget {
  const ReturningLoginScreen({super.key});

  @override
  ConsumerState<ReturningLoginScreen> createState() =>
      _ReturningLoginScreenState();
}

class _ReturningLoginScreenState extends ConsumerState<ReturningLoginScreen> {
  static const int _len = 6;
  String _pin = '';
  bool _busy = false;
  String? _error;
  String? _phone;

  @override
  void initState() {
    super.initState();
    // The login identifier was kept on logout (secure storage) — load it for display + the login.
    Future.microtask(() async {
      final phone = await ref.read(appStoreProvider).readPhone();
      if (mounted) setState(() => _phone = phone);
    });
  }

  Future<void> _onDigit(String d) async {
    if (_busy || _pin.length >= _len) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == _len) await _submit();
  }

  void _onBackspace() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    final phone = _phone;
    if (phone == null) {
      // No remembered phone (shouldn't reach `returning` without one) → fall back to a fresh sign-in.
      await ref.read(sessionProvider.notifier).logout(forgetDevice: true);
      return;
    }
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final pin = _pin;
    setState(() => _busy = true);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .loginWithPin(phone: phone, pin: pin);
    if (!mounted) return;
    // ok → session is now authenticated → the router redirects away; nothing to do here.
    if (!ok) {
      setState(() {
        _busy = false;
        _pin = '';
        _error = ref.read(authControllerProvider).error ??
            (isThai ? 'PIN ไม่ถูกต้อง' : 'Incorrect PIN');
      });
    }
  }

  /// "ลืมรหัส PIN" — reset the PIN via OTP: seed the reset run with the remembered phone, keep the
  /// session in `returning` (which permits the /auth flow), then jump into captcha → OTP → new-PIN.
  Future<void> _forgotPin() async {
    final phone = _phone;
    if (phone == null) {
      await ref.read(sessionProvider.notifier).logout(forgetDevice: true);
      return;
    }
    ref.read(authControllerProvider.notifier).startReset(phone);
    ref.read(sessionProvider.notifier).beginPinReset();
    if (!mounted) return;
    context.go('/auth/captcha');
  }

  /// Sign in as a DIFFERENT account: forget this device (drop the phone + local PIN) → OTP flow.
  Future<void> _differentAccount() async {
    await ref.read(sessionProvider.notifier).logout(forgetDevice: true);
  }

  /// A discreet identifier hint — the trailing 4 digits of the remembered phone.
  String _phoneHint(String phone) {
    if (phone.length < 4) return '';
    return '•• ••• ${phone.substring(phone.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final phone = _phone;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: PgTokens.space6),
                  child: Column(
                    children: [
                      const SizedBox(height: PgTokens.space7),
                      const CircleAvatar(
                        radius: 36,
                        backgroundColor: PgTokens.colorGreen100,
                        child: Icon(Icons.person_outline,
                            size: 32, color: PgTokens.colorGreen800),
                      ),
                      const SizedBox(height: PgTokens.space3),
                      Text(isThai ? 'ยินดีต้อนรับกลับ' : 'Welcome back',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: PgTokens.space2),
                      Text(
                          isThai
                              ? 'กรอก PIN เพื่อเข้าสู่ระบบ'
                              : 'Enter your PIN to sign in',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: PgTokens.colorTextMuted, fontSize: 13)),
                      if (phone != null && phone.length >= 4) ...[
                        const SizedBox(height: 2),
                        Text(_phoneHint(phone),
                            style: const TextStyle(
                                color: PgTokens.colorTextMuted, fontSize: 12)),
                      ],
                      const SizedBox(height: PgTokens.space6),
                      PinDots(
                          length: _len,
                          filled: _pin.length,
                          error: _error != null),
                      const SizedBox(height: PgTokens.space3),
                      SizedBox(
                        height: 22,
                        child: _busy
                            ? const Center(
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))
                            : (_error != null
                                ? Text(_error!,
                                    style: const TextStyle(
                                        color: PgTokens.colorDanger))
                                : null),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: PgTokens.space6),
                child: PinKeypad(
                  enabled: !_busy,
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  onBiometric: null,
                ),
              ),
              PgGhostButton(
                label: isThai ? 'ลืมรหัส PIN?' : 'Forgot PIN?',
                onPressed: _busy ? null : _forgotPin,
              ),
              TextButton(
                onPressed: _busy ? null : _differentAccount,
                child: Text(
                  isThai ? 'เข้าด้วยบัญชีอื่น' : 'Use a different account',
                  style: const TextStyle(
                      fontSize: 13, color: PgTokens.colorTextMuted),
                ),
              ),
              const SizedBox(height: PgTokens.space3),
            ],
          ),
        ),
      ),
    );
  }
}
