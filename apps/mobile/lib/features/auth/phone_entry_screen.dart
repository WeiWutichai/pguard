import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../widgets/auth_head.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// Step 1: phone number only. UI per `Mobile - Auth.html` screen ① (กรอกเบอร์โทร) — centered
/// welcome hero (pguard mark + title/subtitle) + a 🇹🇭 +66 field with a prefix divider and a
/// 4px focus-ring glow, then "ขอรหัส OTP". The bot-check (math captcha) is NOT on this screen
/// anymore: it is its own step shown AFTER the phone is entered ([CaptchaScreen]), so this
/// screen matches the design (which goes phone → OTP with no captcha clutter).
class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final TextEditingController _phone = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _localError;

  @override
  void initState() {
    super.initState();
    // Restore the number if the user came back from the captcha/OTP step.
    _phone.text = ref.read(authControllerProvider).phone;
    // Repaint the focus-ring glow as focus moves (design: 0 0 0 4px --focus-ring).
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _phone.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Validate locally, then hand off to the captcha step (which solves the bot-check and actually
  /// requests the OTP SMS). No network call here — the phone screen stays clean per the design.
  void _continue() {
    final ctrl = ref.read(authControllerProvider.notifier);
    final phone = _phone.text.trim();
    ctrl.setPhone(phone);
    if (!ctrl.isValidPhone(phone)) {
      setState(() => _localError = 'เบอร์โทรไม่ถูกต้อง / Invalid phone number');
      return;
    }
    setState(() => _localError = null);
    context.push('/auth/captcha');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PGuardHeader(title: 'pguard', subtitle: 'เข้าสู่ระบบ · Sign in'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space4),
              const AuthHead(
                showLogo: true,
                title: 'ยินดีต้อนรับสู่ pguard / Welcome to pguard',
                subtitle:
                    'กรอกเบอร์โทรเพื่อรับรหัส OTP / Enter your phone to get an OTP',
              ),
              const SizedBox(height: PgTokens.space6),
              // Design `.phone-field` focus: brand border (theme) + a 4px focus-ring glow.
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                  boxShadow: _focusNode.hasFocus
                      ? const [
                          BoxShadow(
                              color: PgTokens.colorFocusRing,
                              blurRadius: 0,
                              spreadRadius: 4)
                        ]
                      : null,
                ),
                child: TextField(
                  controller: _phone,
                  focusNode: _focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  // Spaced digits to echo the design's `81 234 5678` field.
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (v) {
                    ref.read(authControllerProvider.notifier).setPhone(v);
                    if (_localError != null) setState(() => _localError = null);
                  },
                  onSubmitted: (_) => _continue(),
                  decoration: const InputDecoration(
                    labelText: 'เบอร์โทรศัพท์ / Phone',
                    hintText: '81 234 5678',
                    // Design prefix: '🇹🇭 +66' 17/600 muted with a 1px divider before the digits.
                    prefixIcon: _PhonePrefix(),
                    prefixIconConstraints:
                        BoxConstraints(minWidth: 0, minHeight: 0),
                  ),
                ),
              ),
              const SizedBox(height: PgTokens.space2),
              const Text(
                'เราจะส่ง SMS รหัส 6 หลักไปยังเบอร์นี้ / We\'ll text a 6-digit code to this number',
                textAlign: TextAlign.center,
                style: TextStyle(color: PgTokens.colorTextMuted, fontSize: 12.5),
              ),
              const SizedBox(height: PgTokens.space6),
              if (_localError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: PgTokens.space3),
                  child: Text(
                    _localError!,
                    style: const TextStyle(color: PgTokens.colorDanger),
                  ),
                ),
              PgPrimaryButton(
                label: 'ขอรหัส OTP / Send OTP',
                onPressed: _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The design's `.phone-field` prefix: '🇹🇭 +66' (17/600, muted) with 10px right padding and
/// a 1px `--border` divider before the digits.
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
