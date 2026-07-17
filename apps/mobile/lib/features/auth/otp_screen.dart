import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/registration_controller.dart';
import '../../core/controllers/resend_policy.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/models/registration.dart';
import '../../widgets/auth_head.dart';
import '../../widgets/otp_input.dart';
import '../../widgets/pg_auth_back_bar.dart';

/// Step 2: enter the 6-digit OTP. UI per `Mobile - Auth.html` screen ② — centered head,
/// 6 OTP boxes that auto-submit on the 6th digit (no footer CTA in the design), and a
/// centered resend countdown with the attempt counter. The countdown is a pure display
/// ticker (NOT polling, and NOT the booking-status path).
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const ResendPolicy _resend = ResendPolicy();
  String _code = '';

  /// Covers the WHOLE submit flow (verify → phone-status → navigation), not just the guarded
  /// `verifyOtp` call, so the spinner never blinks off between hops — and doubles as a re-entrancy
  /// latch so a double auto-submit (IME repeat / keyboard action + onChanged) can't fire twice.
  bool _verifying = false;

  Future<void> _verify() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      await _runVerify();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _runVerify() async {
    final ok = await ref.read(authControllerProvider.notifier).verifyOtp(_code);
    if (!ok || !mounted) return;
    // ADD-SECOND-ROLE run (from the pending screen): skip the PIN step (the account already has
    // one) — exchange the just-verified token for the second role via `POST /auth/register/add-role`
    // and go straight to that role's profile form. A normal register/reset run continues to the PIN.
    final target = ref.read(authControllerProvider).addRoleTarget;
    if (target != null) {
      final role = RegistrationRole.tryParse(target);
      if (role == null) {
        // Unreachable via the current caller (startAddRolePending passes a real role's wire, which
        // always round-trips), but never silently `return` and strand the user on the OTP screen —
        // bounce back to the pending screen this add-role run came from.
        context.go('/auth/pending');
        return;
      }
      final outcome = await ref
          .read(registrationControllerProvider.notifier)
          .addSecondRoleWhilePending(role);
      if (!mounted) return;
      if (outcome == RegisterOutcome.needsProfile) {
        context.push(
            role.isGuard ? '/auth/register/guard' : '/auth/register/customer');
      } else {
        // 409 already-held / error → surface the controller's message and bounce back to pending.
        final msg = ref.read(registrationControllerProvider).error;
        if (msg != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
        context.go('/auth/pending');
      }
      return;
    }
    // Normal register run: if this phone ALREADY has an account (e.g. "use different account" → the
    // SAME number, which wiped the local PIN), it's a RETURNING user — send them to PIN-LOGIN to
    // enter their EXISTING PIN (server-verified; no local hash needed), NOT a fresh set-PIN. Skip for
    // the forgot-PIN reset, which intentionally sets a new PIN.
    final auth = ref.read(authControllerProvider);
    if (!auth.reset &&
        await ref.read(authControllerProvider.notifier).phoneHasAccount()) {
      if (!mounted) return;
      await ref
          .read(sessionProvider.notifier)
          .toReturningLogin(phone: auth.phone);
      if (!mounted) return;
      // Navigate to PIN-login EXPLICITLY — do NOT trust the session redirect to do it. The
      // `returning` redirect deliberately KEEPS /auth/* reachable (so a reset-PIN / different-account
      // OTP run can start from a remembered device), so `sessionRedirect(returning, '/auth/otp')`
      // returns null (STAY) and never bounces us off the OTP screen. Relying on it left a returning
      // user stranded here with the code entered, no error, and no forward progress (the "กรอก OTP
      // แล้วค้าง" hang). This mirrors role_selection_screen, which likewise `go`es to /login/pin after
      // its own `toReturningLogin` (the register-409 path). The router allows `returning → /login/pin`.
      context.go('/login/pin');
      return;
    }
    if (!mounted) return;
    context.push('/auth/pin');
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(authControllerProvider);
    final sentAt = state.otpSentAt;

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
                title: isThai ? 'กรอกรหัส 6 หลัก' : 'Enter 6-digit code',
                subtitle: isThai
                    ? 'ส่งไปที่ +66 ${state.phone}'
                    : 'Sent to +66 ${state.phone}',
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
              // While the code is being checked, show a spinner instead of the resend line so a
              // running verify is never mistaken for a hang (the screen has no submit button).
              if (_verifying)
                const Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              else if (sentAt != null)
                _ResendCountdown(
                  sentAt: sentAt,
                  policy: _resend,
                  attempt: state.otpRequestCount.clamp(1, 5),
                  isThai: isThai,
                ),
              const SizedBox(height: PgTokens.space4),
              if (state.error != null)
                Text(
                  state.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PgTokens.colorDanger),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The design `.resend` line: "ส่งรหัสอีกครั้งใน 0:42 · พยายาม 1/5" centered, 13px muted, with the
/// timer and attempt counter emphasized in the faint ink. Once elapsed it becomes a Resend action
/// that returns to the captcha step to re-solve the bot-check (which re-sends the SMS to the same
/// number). Rebuilds once per second via a display stream (no network poll).
class _ResendCountdown extends StatelessWidget {
  const _ResendCountdown(
      {required this.sentAt,
      required this.policy,
      required this.attempt,
      required this.isThai});

  final DateTime sentAt;
  final ResendPolicy policy;
  final int attempt;
  final bool isThai;

  static const TextStyle _strong =
      TextStyle(fontWeight: FontWeight.w600, color: PgTokens.colorTextFaint);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final remaining =
            policy.secondsRemaining(sentAt, DateTime.now().toUtc());
        if (remaining > 0) {
          final timer = policy.format(remaining);
          return Text.rich(
            TextSpan(
              children: isThai
                  ? [
                      const TextSpan(text: 'ส่งรหัสอีกครั้งใน '),
                      TextSpan(text: timer, style: _strong),
                      const TextSpan(text: ' · พยายาม '),
                      TextSpan(text: '$attempt/5', style: _strong),
                    ]
                  : [
                      const TextSpan(text: 'Resend in '),
                      TextSpan(text: timer, style: _strong),
                      const TextSpan(text: ' · attempt '),
                      TextSpan(text: '$attempt/5', style: _strong),
                    ],
            ),
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: PgTokens.colorTextMuted, fontSize: 13),
          );
        }
        return Center(
          child: TextButton(
            onPressed: () => context.go('/auth/captcha'),
            child: Text(isThai ? 'ไม่ได้รับรหัส? ขอใหม่' : 'Resend code'),
          ),
        );
      },
    );
  }
}
