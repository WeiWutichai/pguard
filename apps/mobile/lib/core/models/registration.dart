// Registration domain — pure (no Flutter, no I/O) → unit-testable. The v2 flow sets the role at
// register (simpler than v1's progressive onboarding): phone → OTP → PIN → role → POST /auth/register
// (202, NO tokens, pending) → POST /profile/{role} with the single-use profile_token → pending screen.
//
// v2 CONTRACT REALITY (contracts/openapi/{identity,profile}.yaml — source of truth, leaner than the
// v1-shaped UX): the guard profile is JSON (gender/dob/experience/workplace/bank), has NO name field
// and — critically — NO document-upload endpoint (profile.yaml is JSON-only); the customer profile is
// just full_name + address (no company/email). Document images are still captured with a REAL picker
// (an onboarding requirement) and held for the future upload endpoint — see RegistrationController.

/// The role chosen at registration. `admin` is never self-assignable (identity rejects it 403).
enum RegistrationRole {
  guard('guard'),
  customer('customer');

  const RegistrationRole(this.wire);

  /// The wire value sent as `role` to `POST /auth/register` and the `/profile/{role}` path segment.
  final String wire;

  bool get isGuard => this == RegistrationRole.guard;

  static RegistrationRole? tryParse(String? value) {
    for (final r in RegistrationRole.values) {
      if (r.wire == value) return r;
    }
    return null;
  }
}

/// The five guard document images collected during onboarding (real `image_picker`). NOTE: v2
/// `profile.yaml` exposes NO document-upload endpoint and `UpsertGuardProfileRequest` carries no
/// document fields — so these are captured + validated client-side and handed to a deferred upload
/// seam (flagged in the PR). The JSON profile (gender/dob/experience/workplace/bank) is what
/// `POST /profile/guard` actually persists.
enum GuardDocKind {
  idCard('id_card', 'บัตรประชาชน', 'ID card'),
  securityLicense('security_license', 'ใบอนุญาต รปภ.', 'Security license'),
  trainingCert('training_cert', 'ใบรับรองการอบรม', 'Training certificate'),
  criminalCheck(
      'criminal_check', 'ผลตรวจประวัติอาชญากรรม', 'Criminal record check'),
  driverLicense('driver_license', 'ใบขับขี่', 'Driver license');

  const GuardDocKind(this.key, this.labelTh, this.labelEn);

  final String key;
  final String labelTh;
  final String labelEn;
}

/// Non-sensitive prefs keys for the pending-registration flag + masked summary (SharedPreferences,
/// never secure storage — the bank number stored here is ALREADY masked). The session controller
/// reads [kRegPendingRoleKey] on cold start to resume the pending screen.
const String kRegPendingRoleKey = 'pg_reg_pending_role';
const String kRegSummaryKey = 'pg_reg_summary';

/// Durable marker (SharedPreferences — non-sensitive, just a stage label, no PII) set when the
/// user finishes the first onboarding segment (phone→OTP→PIN) and reaches role-select but has
/// NOT registered yet. The session controller reads it on cold start to resume at `/auth/role`
/// instead of bouncing to phone entry. Value is the literal stage (`'role'`); cleared on every
/// onboarding exit path. The raw PIN + phone + phone-verified token that make the resume
/// actionable live in secure storage (see [SessionStore.saveOnboardingPin]).
const String kRegOnboardingStageKey = 'pg_reg_onboarding_stage';
const String kRegOnboardingStageRole = 'role';

/// Mask a bank account number to its last 4 digits for LOCAL persistence/display (PDPA). The full
/// number is sent only to the backend (`account_number`, which the server stores and re-masks on
/// reads). Pure → unit-tested.
String maskAccountNumber(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.length <= 4) return '•' * digits.length;
  final last4 = digits.substring(digits.length - 4);
  return '${'•' * (digits.length - 4)}$last4';
}

/// A masked, non-sensitive summary of a submitted profile — shown on the pending screen and
/// persisted to prefs so a cold start can re-render it. Bank numbers here are ALREADY masked.
class RegistrationSummary {
  const RegistrationSummary({required this.role, required this.lines});

  final RegistrationRole role;

  /// Ordered (label, value) display rows. Values are display-safe (bank no. masked).
  final List<({String label, String value})> lines;

  Map<String, dynamic> toJson() => {
        'role': role.wire,
        'lines': [
          for (final l in lines) {'label': l.label, 'value': l.value},
        ],
      };

  static RegistrationSummary? tryFromJson(Map<String, dynamic> json) {
    final role = RegistrationRole.tryParse(json['role'] as String?);
    if (role == null) return null;
    final raw = (json['lines'] as List?) ?? const [];
    return RegistrationSummary(
      role: role,
      lines: [
        for (final e in raw)
          if (e is Map)
            (
              label: (e['label'] as String?) ?? '',
              value: (e['value'] as String?) ?? '',
            ),
      ],
    );
  }
}
