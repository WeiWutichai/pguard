import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/registration_controller.dart';
import '../../../widgets/pg_auth_back_bar.dart';
import '../../../widgets/primary_button.dart';

/// Customer profile form — `POST /profile/customer` with the single-use `profile_token`. The v2
/// contract is just `full_name` + `address` (no company/email — those don't exist in
/// `UpsertCustomerProfileRequest`). Address is required (min length, with a live ✓ helper once
/// valid); name is optional and follows the design's "(ไม่บังคับ)" pattern. The CTA is the
/// customer-flow amber (`.cta-amber`) — the guard flow keeps green.
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

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  bool get _addressValid => _address.text.trim().length >= _minAddress;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ctrl = ref.read(registrationControllerProvider.notifier);
    final ok = await ctrl.submitCustomerProfile(
      fullName: _name.text,
      address: _address.text,
    );
    if (ok && mounted) context.push('/auth/pending');
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(registrationControllerProvider);

    return Scaffold(
      // No green bar (hi-fi uses a bare back chevron); the body already shows the
      // "ตั้งค่าบัญชีลูกค้า" / "Set up your account" heading the design specifies.
      appBar: const PgAuthBackBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: PgTokens.space2),
                Text(
                  isThai ? 'ตั้งค่าบัญชีลูกค้า' : 'Set up your account',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorText,
                  ),
                ),
                const SizedBox(height: PgTokens.space1),
                Text(
                  isThai
                      ? 'เพื่อจองและรับใบเสร็จ'
                      : 'To book guards & get receipts',
                  style: const TextStyle(
                    fontSize: 13,
                    color: PgTokens.colorTextMuted,
                  ),
                ),
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
                const SizedBox(height: PgTokens.space6),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: PgTokens.space3),
                    child: Text(state.error!,
                        style: const TextStyle(color: PgTokens.colorDanger)),
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
