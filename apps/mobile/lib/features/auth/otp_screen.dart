import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/resend_policy.dart';
import '../../widgets/otp_input.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// Step 2: enter the 6-digit OTP. UI per `Mobile - Auth.html`. The resend countdown is a
/// pure display ticker (NOT polling, and NOT the booking-status path).
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const ResendPolicy _resend = ResendPolicy();
  String _code = '';

  Future<void> _verify() async {
    final ok = await ref.read(authControllerProvider.notifier).verifyOtp(_code);
    if (ok && mounted) context.push('/auth/pin');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final sentAt = state.otpSentAt;

    return Scaffold(
      appBar: const PGuardHeader(
          title: 'ยืนยันรหัส OTP', subtitle: 'Verify code', showBack: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space4),
              Text(
                'กรอกรหัส 6 หลักที่ส่งไปยัง +66 ${state.phone}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: PgTokens.space6),
              OtpInput(
                error: state.error != null,
                onChanged: (v) => _code = v,
                onCompleted: (v) {
                  _code = v;
                  _verify();
                },
              ),
              const SizedBox(height: PgTokens.space4),
              if (sentAt != null)
                _ResendCountdown(sentAt: sentAt, policy: _resend),
              const SizedBox(height: PgTokens.space4),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: PgTokens.space3),
                  child: Text(state.error!,
                      style: const TextStyle(color: PgTokens.colorDanger)),
                ),
              PgPrimaryButton(
                label: 'ยืนยัน / Verify',
                busy: state.busy,
                onPressed: _code.length == 6 ? _verify : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows "Resend in m:ss" counting down, then a Resend action that returns to the phone step
/// to re-solve the captcha. Rebuilds once per second via a display stream (no network poll).
class _ResendCountdown extends StatelessWidget {
  const _ResendCountdown({required this.sentAt, required this.policy});

  final DateTime sentAt;
  final ResendPolicy policy;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final remaining =
            policy.secondsRemaining(sentAt, DateTime.now().toUtc());
        if (remaining > 0) {
          return Text(
            'ขอรหัสใหม่ได้ใน ${policy.format(remaining)} · Resend in ${policy.format(remaining)}',
            style:
                const TextStyle(color: PgTokens.colorTextMuted, fontSize: 13),
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.go('/auth/phone'),
            child: const Text('ไม่ได้รับรหัส? ขอใหม่ / Resend code'),
          ),
        );
      },
    );
  }
}
