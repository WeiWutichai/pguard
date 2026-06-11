import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// Step 1b: bot-check (math captcha), shown AFTER the phone is entered and BEFORE the OTP SMS is
/// sent. The backend gates `POST /otp/request` on a solved challenge (SMS-cost / abuse guard), but
/// the design (`Mobile - Auth.html`) keeps the phone screen clean — so the captcha lives on its own
/// step here. Solving it requests the OTP and advances to the OTP screen.
class CaptchaScreen extends ConsumerStatefulWidget {
  const CaptchaScreen({super.key});

  @override
  ConsumerState<CaptchaScreen> createState() => _CaptchaScreenState();
}

class _CaptchaScreenState extends ConsumerState<CaptchaScreen> {
  final TextEditingController _answer = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Fetch the challenge once after first frame (controller owns the network call).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).loadChallenge();
    });
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final ctrl = ref.read(authControllerProvider.notifier);
    final ok = await ctrl.sendOtp(_answer.text.trim());
    if (ok && mounted) context.push('/auth/otp');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final ctrl = ref.read(authControllerProvider.notifier);
    final question = state.challenge?.question;

    return Scaffold(
      appBar: const PGuardHeader(
          title: 'ยืนยันว่าไม่ใช่บอท', subtitle: 'Quick check', showBack: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space4),
              const Text(
                'ยืนยันว่าไม่ใช่บอท',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: PgTokens.space1),
              Text(
                'ตอบคำถามเพื่อส่งรหัส OTP ไปยัง +66 ${state.phone} / Solve to send your OTP',
                style: const TextStyle(color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space6),
              Container(
                padding: const EdgeInsets.all(PgTokens.space4),
                decoration: BoxDecoration(
                  color: PgTokens.colorSunken,
                  borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question == null
                          ? 'กำลังโหลดคำถาม… / Loading…'
                          : 'คำถาม / Question:  $question',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const SizedBox(height: PgTokens.space2),
                    TextField(
                      controller: _answer,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (_) {
                        if (state.challenge != null) _verify();
                      },
                      decoration:
                          const InputDecoration(hintText: 'คำตอบ / Answer'),
                    ),
                  ],
                ),
              ),
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
                label: 'ยืนยันและส่ง OTP / Verify & send',
                busy: state.busy,
                onPressed: state.challenge == null ? null : _verify,
              ),
              TextButton(
                onPressed: state.busy ? null : ctrl.loadChallenge,
                child: const Text('โหลดคำถามใหม่ / Reload question'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
