import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/registration_controller.dart';
import '../../../widgets/pguard_header.dart';
import '../../../widgets/primary_button.dart';

/// Customer profile form — `POST /profile/customer` with the single-use `profile_token`. The v2
/// contract is just `full_name` + `address` (no company/email — those don't exist in
/// `UpsertCustomerProfileRequest`). Address is required (min length); name is optional.
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
    final state = ref.watch(registrationControllerProvider);

    return Scaffold(
      appBar: const PGuardHeader(
        title: 'ข้อมูลลูกค้า',
        subtitle: 'Customer details',
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
                const Text(
                  'กรอกข้อมูลเพื่อใช้ในการจอง',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: PgTokens.space6),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อ-นามสกุล / Full name (optional)',
                  ),
                ),
                const SizedBox(height: PgTokens.space4),
                TextFormField(
                  controller: _address,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'ที่อยู่ / Address',
                    hintText: 'บ้านเลขที่ ถนน แขวง/ตำบล เขต/อำเภอ จังหวัด',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) {
                      return 'กรุณากรอกที่อยู่ / Address is required';
                    }
                    if (t.length < _minAddress) {
                      return 'ที่อยู่สั้นเกินไป / Address is too short';
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
                PgPrimaryButton(
                  label: 'บันทึกและส่ง / Submit',
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
