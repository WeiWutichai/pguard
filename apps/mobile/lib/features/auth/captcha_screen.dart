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
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(authControllerProvider);
    final ctrl = ref.read(authControllerProvider.notifier);
    final question = state.challenge?.question;

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
                title: isThai ? 'ยืนยันว่าไม่ใช่บอท' : 'Quick check',
                subtitle: isThai
                    ? 'ตอบคำถามเพื่อส่งรหัส OTP ไปที่ +66 ${state.phone}'
                    : 'Solve to send the OTP to +66 ${state.phone}',
              ),
              const SizedBox(height: PgTokens.space6),
              // Design question card: white surface, 1.5px strong border, radius 16 (→ radiusXl).
              Container(
                padding: const EdgeInsets.fromLTRB(
                    PgTokens.space4, PgTokens.space4, PgTokens.space4, 18),
                decoration: BoxDecoration(
                  color: PgTokens.colorSurface,
                  border:
                      Border.all(color: PgTokens.colorBorderStrong, width: 1.5),
                  borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isThai ? 'คำถาม' : 'Question',
                      style: const TextStyle(
                          fontSize: 12.5, color: PgTokens.colorTextMuted),
                    ),
                    const SizedBox(height: PgTokens.space1),
                    // Big bold math problem (design: 26/700 mono).
                    Text(
                      question ?? (isThai ? 'กำลังโหลดคำถาม…' : 'Loading…'),
                      style: question == null
                          ? const TextStyle(
                              fontSize: 12.5, color: PgTokens.colorTextMuted)
                          : const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'IBMPlexMono',
                              color: PgTokens.colorText,
                            ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _answer,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (_) {
                        if (state.challenge != null) _verify();
                      },
                      decoration: InputDecoration(
                          hintText: isThai ? 'คำตอบ' : 'Answer'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: PgTokens.space3),
              Text(
                isThai
                    ? 'ช่วยกันบอทและกันการส่ง SMS เกินจำเป็น'
                    : 'Helps stop bots and unwanted SMS',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, color: PgTokens.colorTextMuted),
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
                label: isThai ? 'ยืนยันและส่ง OTP' : 'Verify & send OTP',
                busy: state.busy,
                onPressed: state.challenge == null ? null : _verify,
              ),
              TextButton(
                onPressed: state.busy ? null : ctrl.loadChallenge,
                child: Text(isThai ? 'โหลดคำถามใหม่' : 'Reload question'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
