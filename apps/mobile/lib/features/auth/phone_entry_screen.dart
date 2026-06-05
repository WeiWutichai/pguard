import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// Step 1: phone number + math captcha → request the OTP SMS. UI per `Mobile - Auth.html`.
class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _answer = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Fetch the captcha once after first frame (controller owns the network call).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).loadChallenge();
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ctrl = ref.read(authControllerProvider.notifier);
    ctrl.setPhone(_phone.text.trim());
    final ok = await ctrl.sendOtp(_answer.text.trim());
    if (ok && mounted) context.push('/auth/otp');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final ctrl = ref.read(authControllerProvider.notifier);

    return Scaffold(
      appBar: const PGuardHeader(
          title: 'pguard', subtitle: 'ยินดีต้อนรับ · Welcome'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space4),
              const Text(
                'เข้าสู่ระบบด้วยเบอร์โทร',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: PgTokens.space1),
              const Text(
                "We'll text a 6-digit code to this number",
                style: TextStyle(color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space6),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                onChanged: ctrl.setPhone,
                decoration: const InputDecoration(
                  prefixText: '+66  ',
                  labelText: 'เบอร์โทรศัพท์ / Phone',
                  hintText: '0812345678',
                ),
              ),
              const SizedBox(height: PgTokens.space4),
              _CaptchaField(
                  question: state.challenge?.question, answer: _answer),
              const SizedBox(height: PgTokens.space4),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: PgTokens.space3),
                  child: Text(
                    state.error!,
                    style: const TextStyle(color: PgTokens.colorDanger),
                  ),
                ),
              PgPrimaryButton(
                label: 'ขอรหัส OTP / Send code',
                busy: state.busy,
                onPressed: state.challenge == null ? null : _submit,
              ),
              TextButton(
                onPressed: state.busy ? null : ctrl.loadChallenge,
                child: const Text('โหลดแคปต์ชาใหม่ / Reload captcha'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptchaField extends StatelessWidget {
  const _CaptchaField({required this.question, required this.answer});

  final String? question;
  final TextEditingController answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ยืนยันว่าไม่ใช่บอท · ${question ?? 'กำลังโหลด…'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: PgTokens.space2),
          TextField(
            controller: answer,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(hintText: 'คำตอบ / Answer'),
          ),
        ],
      ),
    );
  }
}
