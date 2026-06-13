import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../widgets/auth_head.dart';
import '../../widgets/primary_button.dart';
import '../../features/profile/widgets/lang_segmented.dart';

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
  bool _invalidPhone = false;

  @override
  void initState() {
    super.initState();
    // Restore the number if the user came back from the captcha/OTP step. State holds the
    // canonical national `0XXXXXXXXX`; the field sits behind a `+66` prefix, so drop the
    // trunk `0` for display (`812345678`) — matching how it was typed, no redundant `+66 0…`.
    final saved = ref.read(authControllerProvider).phone;
    _phone.text = saved.startsWith('0') ? saved.substring(1) : saved;
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
    // The field shows a fixed `+66` prefix, so the user types the 9-digit significant number
    // (or, by habit, the full `0…` national). Canonicalize to `0XXXXXXXXX` once here so the
    // whole downstream flow (OTP request/verify, register, login identifier) carries the same
    // backend-shaped phone — never the raw `+66`-relative digits the backend would reject.
    final normalized = AuthController.normalizeThaiPhone(_phone.text);
    if (normalized == null) {
      ctrl.setPhone(_phone.text.trim());
      setState(() => _invalidPhone = true);
      return;
    }
    ctrl.setPhone(normalized);
    setState(() => _invalidPhone = false);
    context.push('/auth/captcha');
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    // No green top bar — the hi-fi `Mobile - Auth.html` screen ① has none; the brand shows
    // via the centered shield + welcome below. AnnotatedRegion gives the light page the dark
    // status-bar icons the (removed) green header used to set.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PgTokens.space6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Language toggle, top-right — pre-login users choose TH/EN here (the only
                // other place it lives is the post-login profile). Default is Thai.
                Align(
                  alignment: Alignment.centerRight,
                  child: LangSegmented(
                    value: ref.watch(localeControllerProvider),
                    onChanged: (l) => ref
                        .read(localeControllerProvider.notifier)
                        .setLocale(l),
                  ),
                ),
                const SizedBox(height: PgTokens.space2),
                AuthHead(
                  showLogo: true,
                  title:
                      isThai ? 'ยินดีต้อนรับสู่ pguard' : 'Welcome to pguard',
                  subtitle: isThai
                      ? 'กรอกเบอร์โทรเพื่อรับรหัส OTP'
                      : 'Enter your phone to get an OTP',
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
                    // Spaced mono digits to echo the design's `81 234 5678` field.
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'IBMPlexMono',
                        letterSpacing: 1.2),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onChanged: (v) {
                      ref.read(authControllerProvider.notifier).setPhone(v);
                      if (_invalidPhone) {
                        setState(() => _invalidPhone = false);
                      }
                    },
                    onSubmitted: (_) => _continue(),
                    // No floating label — the hi-fi field is just the +66 prefix + the number
                    // (a Material `labelText` would float up and overlap the rounded border).
                    // The "phone" context comes from the title above + the +66 prefix.
                    decoration: const InputDecoration(
                      hintText: '81 234 5678',
                      // Design prefix: '🇹🇭 +66' 17/600 muted with a 1px divider before the digits.
                      prefixIcon: _PhonePrefix(),
                      prefixIconConstraints:
                          BoxConstraints(minWidth: 0, minHeight: 0),
                    ),
                  ),
                ),
                const SizedBox(height: PgTokens.space2),
                Text(
                  isThai
                      ? 'เราจะส่ง SMS รหัส 6 หลักไปยังเบอร์นี้'
                      : "We'll text a 6-digit code to this number",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: PgTokens.colorTextMuted, fontSize: 12.5),
                ),
                const SizedBox(height: PgTokens.space6),
                if (_invalidPhone)
                  Padding(
                    padding: const EdgeInsets.only(bottom: PgTokens.space3),
                    child: Text(
                      isThai ? 'เบอร์โทรไม่ถูกต้อง' : 'Invalid phone number',
                      style: const TextStyle(color: PgTokens.colorDanger),
                    ),
                  ),
                PgPrimaryButton(
                  label: isThai ? 'ขอรหัส OTP' : 'Send OTP',
                  onPressed: _continue,
                ),
              ],
            ),
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
