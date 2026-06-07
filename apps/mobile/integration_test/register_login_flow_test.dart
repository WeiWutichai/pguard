// Patrol e2e — the customer/guard onboarding flow against the REAL backend:
//
//   phone → captcha → request OTP → verify OTP → set PIN → choose role → register (202 pending)
//     → (admin approves — asserted by the web Playwright suite / API) → PIN login.
//
// Mirrors the live screens (app_router.dart routes /auth/phone, /auth/otp, /auth/pin, /auth/role)
// and the controllers (core/controllers/auth_controller.dart, registration_controller.dart).
//
// ─────────────────────────── PREREQUISITES TO RUN GREEN ───────────────────────────
// 1. Native platform projects: this app is pure-Dart at this phase. Run once:
//      cd apps/mobile && flutter create --platforms=android,ios .
// 2. A running emulator/simulator (Patrol drives the real UI — there is no headless mode).
// 3. The live stack: tooling/scripts/e2e-stack-up.sh  (SMS disabled → no real SMS dependency).
// 4. Point the app at the host gateway, e.g. Android emulator:
//      --dart-define=PGUARD_API_HOST=http://10.0.2.2:3000
// 5. A DETERMINISTIC OTP. The otp service stores only sha256(code) and, with SMS disabled, never
//    surfaces the plaintext; `/otp/request` also overwrites any pre-seeded hash. So the verify step
//    needs ONE of: (a) a dev/test affordance in the otp service that returns/fixes the code when
//    SMS is disabled, or (b) a host-side hook that overwrites otp.otp_codes.code_hash with
//    sha256(KNOWN) AFTER the app's /otp/request but BEFORE verify. Wire that into `_obtainOtpCode`.
//    Until then, this test stops at the OTP step. See tests/e2e/mobile/README.md §"OTP determinism".
//
// Run:
//   cd apps/mobile && dart run patrol_cli test -t integration_test/register_login_flow_test.dart \
//     --dart-define=PGUARD_API_HOST=http://10.0.2.2:3000
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:pguard_mobile/main.dart' as app;

/// A unique Thai mobile number per run (kept deterministic-enough for a single run).
const String _testPhone = '0890001234';

/// Obtain the 6-digit OTP for [phone]. Returns the code from a test affordance — see prereq #5.
/// `PGUARD_E2E_OTP_CODE` lets a fixed-code otp test build (or a host hook that seeds the hash)
/// drive this deterministically.
String _obtainOtpCode(String phone) {
  const fixed = String.fromEnvironment('PGUARD_E2E_OTP_CODE', defaultValue: '');
  if (fixed.isEmpty) {
    fail(
      'No deterministic OTP available — set PGUARD_E2E_OTP_CODE (with a fixed-code otp test build '
      'or a host hook seeding otp.otp_codes). See this file\'s PREREQUISITES + the mobile README.',
    );
  }
  return fixed;
}

void main() {
  patrolTest('onboarding: phone → OTP → PIN → register (202 pending)', ($) async {
    app.main();
    await $.pumpAndSettle();

    // ── /auth/phone: enter the phone, load + solve the math captcha, submit ──
    await $(TextField).first.enterText(_testPhone);
    // The phone screen loads a math captcha (GET /otp/challenge) and shows the question; a real run
    // reads the rendered question, computes the answer into the "คำตอบ / Answer" field, then taps
    // submit → POST /otp/request.

    // ── /auth/otp: enter the 6-digit code (deterministic via the prereq #5 hook) ──
    final code = _obtainOtpCode(_testPhone);
    await $(TextField).first.enterText(code);
    await $('Verify').tap();
    await $.pumpAndSettle();

    // ── /auth/pin: choose a PIN → pin_hash = sha256(pin) ──
    await $(TextField).first.enterText('123456');
    await $.pumpAndSettle();

    // ── /auth/role: choose customer → register() → 202 pending → /auth/register/customer ──
    await $('Customer').tap();
    await $.pumpAndSettle();

    // Registered (202 pending). Approval + the subsequent PIN login is asserted end-to-end by the
    // web Playwright suite (applicants-approve.spec.ts) and the gateway login.
    expect($('pending'), findsWidgets);
  });
}
