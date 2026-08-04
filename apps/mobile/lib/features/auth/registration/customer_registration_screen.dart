import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/registration_controller.dart';
import '../../../widgets/pguard_header.dart';
import '../../../widgets/primary_button.dart';
import '../../legal/terms_screen.dart';

/// Customer profile form — `POST /profile/customer` with the single-use `profile_token`. v1-parity
/// fields: `full_name` + `address` (required) + optional `company_name` / `email` / `contact_phone`.
/// Address is required (min length, with a live ✓ helper once valid); the rest follow the design's
/// "(ไม่บังคับ)" pattern. The CTA is the customer-flow amber (`.cta-amber`) — guard flow keeps green.
class CustomerRegistrationScreen extends ConsumerStatefulWidget {
  const CustomerRegistrationScreen({super.key});

  @override
  ConsumerState<CustomerRegistrationScreen> createState() =>
      _CustomerRegistrationScreenState();
}

class _CustomerRegistrationScreenState
    extends ConsumerState<CustomerRegistrationScreen> {
  static const int _minAddress = 10;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _company.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _addressValid => _address.text.trim().length >= _minAddress;

  /// Label with the design's faint "(ไม่บังคับ)/(optional)" suffix — for the non-required fields.
  InputDecoration _optionalDecoration(String label, bool isThai,
      {IconData? icon}) {
    return InputDecoration(
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 20, color: PgTokens.colorTextMuted),
      label: Text.rich(
        TextSpan(
          text: label,
          children: [
            TextSpan(
              text: isThai ? '(ไม่บังคับ)' : '(optional)',
              style: const TextStyle(
                color: PgTokens.colorTextFaint,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ctrl = ref.read(registrationControllerProvider.notifier);
    final ok = await ctrl.submitCustomerProfile(
      fullName: _name.text,
      address: _address.text,
      companyName: _company.text,
      email: _email.text,
      contactPhone: _phone.text,
    );
    if (ok && mounted) context.push('/auth/pending');
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(registrationControllerProvider);

    return Scaffold(
      // Design: a green TopAppBar (title + subtitle) over a hero banner with the registration
      // overlay, then the form.
      appBar: PGuardHeader(
        title: isThai ? 'ตั้งค่าบัญชีลูกค้า' : 'Customer account',
        subtitle:
            isThai ? 'เพื่อจองและรับใบเสร็จ' : 'To book guards & get receipts',
        showBack: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: PgTokens.space2),
                // Hero banner — branded illustration with the "Registration" overlay.
                _RegHeroBanner(isThai: isThai),
                const SizedBox(height: PgTokens.space6),
                TextFormField(
                  key: const Key('reg_address'),
                  controller: _address,
                  minLines: 3,
                  maxLines: 4,
                  textInputAction: TextInputAction.next,
                  // Rebuild on change so the ✓ helper appears live once the minimum is met.
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    label: Text.rich(
                      TextSpan(
                        text: isThai ? 'ที่อยู่ ' : 'Address ',
                        children: const [
                          TextSpan(
                              text: '*',
                              style: TextStyle(color: PgTokens.colorDanger)),
                        ],
                      ),
                    ),
                    hintText: 'บ้านเลขที่ ถนน แขวง/ตำบล เขต/อำเภอ จังหวัด',
                    alignLabelWithHint: true,
                    helperText: _addressValid
                        ? (isThai
                            ? '✓ ที่อยู่ครบถ้วน (อย่างน้อย 10 ตัวอักษร)'
                            : '✓ Valid (min 10 characters)')
                        : null,
                    helperStyle: const TextStyle(
                        fontSize: 11.5, color: PgTokens.colorSuccess),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) {
                      return isThai
                          ? 'กรุณากรอกที่อยู่'
                          : 'Address is required';
                    }
                    if (t.length < _minAddress) {
                      return isThai
                          ? 'ที่อยู่สั้นเกินไป'
                          : 'Address is too short';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: PgTokens.space4),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    label: Text.rich(
                      TextSpan(
                        text: isThai ? 'ชื่อ-นามสกุล ' : 'Full name ',
                        children: [
                          TextSpan(
                            text: isThai ? '(ไม่บังคับ)' : '(optional)',
                            style: const TextStyle(
                              color: PgTokens.colorTextFaint,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: PgTokens.space4),
                TextFormField(
                  controller: _company,
                  textInputAction: TextInputAction.next,
                  decoration: _optionalDecoration(
                      isThai ? 'ชื่อบริษัท ' : 'Company name ', isThai),
                ),
                const SizedBox(height: PgTokens.space4),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: _optionalDecoration(
                      isThai ? 'อีเมล ' : 'Email ', isThai,
                      icon: Icons.mail_outline),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null; // optional
                    if (t.length < 5 || !t.contains('@') || !t.contains('.')) {
                      return isThai ? 'อีเมลไม่ถูกต้อง' : 'Invalid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: PgTokens.space4),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  decoration: _optionalDecoration(
                      isThai ? 'เบอร์ติดต่อ ' : 'Contact phone ', isThai,
                      icon: Icons.phone_outlined),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null; // optional
                    final digits = t.replaceAll(RegExp(r'\D'), '');
                    if (digits.length < 10 || !digits.startsWith('0')) {
                      return isThai
                          ? 'เบอร์ไม่ถูกต้อง (10 หลักขึ้นต้น 0)'
                          : 'Invalid phone (10 digits, leading 0)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: PgTokens.space6),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: PgTokens.space3),
                    child: Text(state.error!,
                        style: const TextStyle(color: PgTokens.colorDanger)),
                  ),
                // Terms-acceptance notice (design footer). Acceptance itself already happened at the
                // gate before this form opened, so this restates it and the two policy phrases open
                // the document read-only.
                Padding(
                  padding: const EdgeInsets.only(bottom: PgTokens.space3),
                  child: Text.rich(
                    TextSpan(
                      text: isThai ? 'คุณได้ยอมรับ ' : 'You have accepted the ',
                      children: [
                        termsLinkSpan(context,
                            isThai ? 'ข้อตกลงการใช้งาน' : 'Terms of Use'),
                        TextSpan(text: isThai ? ' และ ' : ' and '),
                        termsLinkSpan(
                            context,
                            isThai
                                ? 'นโยบายความเป็นส่วนตัว'
                                : 'Privacy Policy'),
                        TextSpan(
                            text: isThai ? ' ของ pguard แล้ว' : ' of pguard'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: PgTokens.colorTextMuted),
                  ),
                ),
                // `.cta-amber` — the amber CTA distinguishes the customer flow from the guard flow.
                PgPrimaryButton(
                  label: isThai ? 'สร้างบัญชี' : 'Create account',
                  color: PgTokens.colorAccent,
                  foreground: PgTokens.colorOnAmber,
                  busy: state.busy,
                  onPressed: state.busy ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hero banner — the branded illustration (shield + protected home/building) with a
/// "Registration / ข้อมูลความปลอดภัยของคุณ" overlay in the bottom-left, per the design.
class _RegHeroBanner extends StatelessWidget {
  const _RegHeroBanner({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Image.asset(
            'assets/images/customer_reg_hero.png',
            height: 132,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
          // Bottom scrim so the overlay text stays legible over the illustration.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    PgTokens.colorBrand.withValues(alpha: 0.78),
                    PgTokens.colorBrand.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
          Positioned(
            left: PgTokens.space4,
            bottom: PgTokens.space3,
            right: PgTokens.space4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isThai ? 'การลงทะเบียน' : 'REGISTRATION',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isThai ? 'ข้อมูลความปลอดภัยของคุณ' : 'Your security details',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
