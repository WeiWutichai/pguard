import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/registration.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'auth_controller.dart';
import 'locale_controller.dart';
import 'pin_hasher.dart';
import 'session_controller.dart';

part 'registration_controller.g.dart';

/// The result of [RegistrationController.register].
enum RegisterOutcome {
  /// 202 — pending account created; go submit the profile with the `profile_token`.
  needsProfile,

  /// 409 — the phone was already registered (approved/active), so we logged in instead; the
  /// router will redirect to the dashboard.
  loggedIn,

  /// Validation/network/other failure — `state.error` carries a user-safe message.
  error,
}

/// Cross-screen registration state (immutable; secrets are NOT held here — see the notifier).
class RegistrationState {
  const RegistrationState({
    this.role,
    this.busy = false,
    this.error,
    this.submitted,
  });

  final RegistrationRole? role;
  final bool busy;
  final String? error;

  /// The masked summary after a successful profile submit (drives the pending screen).
  final RegistrationSummary? submitted;

  RegistrationState copyWith({
    RegistrationRole? role,
    bool? busy,
    Object? error = _unset,
    RegistrationSummary? submitted,
  }) {
    return RegistrationState(
      role: role ?? this.role,
      busy: busy ?? this.busy,
      error: identical(error, _unset) ? this.error : error as String?,
      submitted: submitted ?? this.submitted,
    );
  }
}

const Object _unset = Object();

/// Owns the multi-screen registration flow AFTER the auth steps (role → register → profile →
/// pending). `keepAlive` because the flow spans several pushed screens (mirrors the booking flow
/// controller); the auth controller stays focused on phone/OTP/PIN.
///
/// IRON RULES enforced here:
///  - `register` on 202 sets the session to **pendingApproval** and stashes the `profile_token`;
///    it NEVER stores access/refresh tokens and NEVER flips to `authenticated` (a pending account
///    can't log in).
///  - the profile submit presents the single-use `profile_token` as the Bearer (the user has no
///    session yet) — `pguardApi.post(..., bearer: token)`.
///  - the bank account number is sent in FULL to the backend but the LOCALLY-persisted summary is
///    masked to last-4 (PDPA) — the full number never touches prefs/secure storage.
///  - a 409 ("already registered") falls back to `loginWithPin` (returning/approved user).
@Riverpod(keepAlive: true)
class RegistrationController extends _$RegistrationController {
  @override
  RegistrationState build() => const RegistrationState();

  // Cross-screen credentials — kept on the notifier, never in the exposed immutable state.
  String? _phone;
  String? _phoneVerifiedToken;
  String? _pin;
  String? _profileToken;

  static const PinHasher _hasher = PinHasher();

  /// Snapshot the auth-flow credentials once the PIN is set (called from the PIN screen) AND
  /// persist them so a cold start before role-select can resume here (Option A) and still
  /// register: phone + raw PIN go to secure storage (the phone-verified token is already there
  /// from `verifyOtp`), and a non-sensitive stage marker goes to prefs. The marker is written
  /// LAST so its presence implies the credentials are already saved (a kill mid-sequence then
  /// resumes to phone, harmless, rather than to role with missing creds).
  Future<void> beginFromAuth({
    required String phone,
    String? phoneVerifiedToken,
    required String pin,
  }) async {
    _phone = phone;
    _phoneVerifiedToken = phoneVerifiedToken;
    _pin = pin;
    final store = ref.read(appStoreProvider);
    final prefs = ref.read(prefsStoreProvider);
    await store.savePhone(phone);
    await store.saveOnboardingPin(pin);
    if (phoneVerifiedToken != null) {
      await store.savePhoneVerifiedToken(phoneVerifiedToken);
    }
    await prefs.setString(kRegOnboardingStageKey, kRegOnboardingStageRole);
    state =
        const RegistrationState(); // fresh flow (clears any stale role/error/summary)
  }

  void selectRole(RegistrationRole role) =>
      state = state.copyWith(role: role, error: null);

  /// `POST /auth/register { phone_verified_token, role, pin_hash }`. On **202** → stash the
  /// `profile_token`, persist the pending flag, flip the session to **pendingApproval** (NO
  /// tokens). On **409** → `loginWithPin` (the phone already exists in a non-pending state).
  Future<RegisterOutcome> register() async {
    // Re-entrancy latch: ignore a duplicate tap while a register is already in flight. busy is set
    // SYNCHRONOUSLY here — BEFORE the storage reads/await below — so the second tap observes it
    // (setting it only after the awaits would leave a window where both taps pass the check).
    if (state.busy) {
      return RegisterOutcome.error;
    }
    state = state.copyWith(busy: true, error: null);
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final role = state.role;
    final store = ref.read(appStoreProvider);
    // Rehydrate from storage when in-memory is empty (cold-start resume at role-select).
    final pvt = _phoneVerifiedToken ?? await store.readPhoneVerifiedToken();
    final pin = _pin ?? await store.readOnboardingPin();
    final phone = _phone ?? await store.readPhone();
    if (role == null || pvt == null || pin == null || phone == null) {
      // A re-tap after a successful 202 lands here (the phone-verified token was cleared) — if the
      // profile_token from that register is still around, the account already exists (pending), so
      // resume to the profile step instead of dead-ending with "start again".
      final resumed = await _resumeIfAlreadyRegistered();
      if (resumed != null) return resumed;
      state = state.copyWith(
          busy: false,
          error: isThai
              ? 'หมดเวลายืนยัน กรุณาเริ่มใหม่'
              : 'Verification expired — start again');
      return RegisterOutcome.error;
    }

    // (busy already set synchronously above.)
    try {
      final data =
          await ref.read(pguardApiProvider).post('/auth/register', data: {
        'phone_verified_token': pvt,
        'role': role.wire,
        'pin_hash': _hasher.pinHash(pin),
      });
      final profileToken = (data is Map<String, dynamic>)
          ? data['profile_token'] as String?
          : null;
      if (profileToken != null) {
        _profileToken = profileToken;
        await store.saveProfileToken(profileToken);
      }
      // Persist the phone (PII, secure storage) now so a cold-start "check status" can log in.
      await store.savePhone(phone);
      // The phone-verified token is now consumed (server burned its jti) — drop it from BOTH
      // memory AND secure storage so backing out of the profile form and re-tapping a role can't
      // re-present a spent token (which would 400 → a confusing "verification expired" bounce).
      // The profile_token is kept (the profile step still needs it).
      _phoneVerifiedToken = null;
      await store.clearPhoneVerifiedToken();
      // The first onboarding segment is over → drop its resume marker + raw PIN so a later cold
      // start routes to the pending screen (set below), not back to role-select. (Keep the
      // profile token + phone, still needed for the profile/check-status step.)
      await _clearOnboardingResume();
      // CRITICAL: pending only — never store access tokens, never flip to authenticated. The
      // prefs pending flag is set only AFTER a successful profile submit (so a kill BETWEEN
      // register and submit doesn't strand the user on the pending screen — they can re-register
      // the still-pending phone, which the contract 202-refreshes).
      ref.read(sessionProvider.notifier).onPendingApproval();
      state = state.copyWith(busy: false);
      return RegisterOutcome.needsProfile;
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        // Already registered (approved/active) — log in with the SAME PIN instead.
        _phoneVerifiedToken =
            null; // not consumed by the rejected register; drop for hygiene
        final ok = await ref
            .read(authControllerProvider.notifier)
            .loginWithPin(phone: phone, pin: pin);
        if (ok) {
          await _clearPending();
          state = state.copyWith(busy: false);
          return RegisterOutcome.loggedIn;
        }
        state = state.copyWith(
            busy: false,
            error: isThai ? 'เข้าสู่ระบบไม่สำเร็จ' : 'Could not sign in');
        return RegisterOutcome.error;
      }
      if (e.statusCode == 401 || e.statusCode == 400) {
        // Stale phone-verified token: 401 = JWT past exp (>10 min), 400 = jti already consumed
        // (identity api/mod.rs GETDEL miss → BadRequest; shared-rust auth.rs decode → Unauthorized).
        // FIRST: if a profile_token already exists, a prior register on this phone SUCCEEDED — the
        // 400 is just a re-presented spent token (back-out + re-tap). Resume to the profile step
        // rather than wiping the pending account and bouncing the user back to phone entry.
        final resumed = await _resumeIfAlreadyRegistered();
        if (resumed != null) return resumed;
        // Genuine expiry / first attempt: the first segment must be redone → wipe + bounce.
        await _abortOnboarding();
        ref.read(authControllerProvider.notifier).reset();
        ref.read(sessionProvider.notifier).onOnboardingExpired();
        state = state.copyWith(
            busy: false,
            error: isThai
                ? 'หมดเวลายืนยัน กรุณาขอรหัสใหม่'
                : 'Verification expired — request a new code');
        return RegisterOutcome.error;
      }
      state = state.copyWith(busy: false, error: e.message);
      return RegisterOutcome.error;
    } catch (_) {
      state = state.copyWith(
          busy: false,
          error: isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong');
      return RegisterOutcome.error;
    }
  }

  /// `POST /profile/customer` with the `profile_token`. Address is required (the screen validates
  /// length); full_name/company_name/email/contact_phone are optional v1-parity fields.
  Future<bool> submitCustomerProfile({
    String? fullName,
    required String address,
    String? companyName,
    String? email,
    String? contactPhone,
  }) {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final name = fullName?.trim();
    final addr = address.trim();
    final company = companyName?.trim();
    final mail = email?.trim();
    final phone = contactPhone?.trim();
    return _submitProfile(
      '/profile/customer',
      {
        if (name != null && name.isNotEmpty) 'full_name': name,
        'address': addr,
        if (company != null && company.isNotEmpty) 'company_name': company,
        if (mail != null && mail.isNotEmpty) 'email': mail,
        if (phone != null && phone.isNotEmpty) 'contact_phone': phone,
      },
      summary: RegistrationSummary(
        role: RegistrationRole.customer,
        lines: [
          if (name != null && name.isNotEmpty)
            (label: isThai ? 'ชื่อ' : 'Name', value: name),
          (label: isThai ? 'ที่อยู่' : 'Address', value: addr),
          if (company != null && company.isNotEmpty)
            (label: isThai ? 'บริษัท' : 'Company', value: company),
          if (mail != null && mail.isNotEmpty)
            (label: isThai ? 'อีเมล' : 'Email', value: mail),
          if (phone != null && phone.isNotEmpty)
            (label: isThai ? 'เบอร์ติดต่อ' : 'Phone', value: phone),
        ],
      ),
    );
  }

  /// `POST /profile/guard` with the `profile_token`. The FULL account number is sent to the
  /// backend; the locally-persisted summary masks it to last-4. `docPaths` are the real-picker
  /// document images — captured + validated client-side and held for the future upload endpoint
  /// (v2 `profile.yaml` has no document-upload route yet; see [GuardDocKind]).
  Future<bool> submitGuardProfile({
    String? fullName,
    String? gender,
    String? dateOfBirth,
    int? yearsOfExperience,
    String? previousWorkplace,
    String? bankName,
    required String accountNumber,
    String? accountName,
    String? address,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelationship,
    Map<GuardDocKind, String> docPaths = const {},
    Map<GuardDocKind, DateTime> docExpiry = const {},
  }) {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final digits = accountNumber.replaceAll(RegExp(r'\D'), '');
    final name = fullName?.trim();
    final bank = bankName?.trim();
    final acctName = accountName?.trim();
    final workplace = previousWorkplace?.trim();
    final addr = address?.trim();
    final ecName = emergencyContactName?.trim();
    final ecPhone = emergencyContactPhone?.trim();
    final ecRel = emergencyContactRelationship?.trim();
    return _submitProfile(
      '/profile/guard',
      {
        if (name != null && name.isNotEmpty) 'full_name': name,
        if (gender != null && gender.isNotEmpty) 'gender': gender,
        if (dateOfBirth != null && dateOfBirth.isNotEmpty)
          'date_of_birth': dateOfBirth,
        if (yearsOfExperience != null) 'years_of_experience': yearsOfExperience,
        if (workplace != null && workplace.isNotEmpty)
          'previous_workplace': workplace,
        if (bank != null && bank.isNotEmpty) 'bank_name': bank,
        'account_number':
            digits, // FULL digits to the backend (server re-masks on reads)
        if (acctName != null && acctName.isNotEmpty) 'account_name': acctName,
        if (addr != null && addr.isNotEmpty) 'address': addr,
        if (ecName != null && ecName.isNotEmpty)
          'emergency_contact_name': ecName,
        if (ecPhone != null && ecPhone.isNotEmpty)
          'emergency_contact_phone': ecPhone,
        if (ecRel != null && ecRel.isNotEmpty)
          'emergency_contact_relationship': ecRel,
        // Per-document expiry dates from the doc step — folded into the profile submit because the
        // single-use profile_token authorizes exactly one write. Server captures them best-effort
        // into document_expiry (feeds the admin "expiring" surface); the image isn't uploaded yet.
        if (docExpiry.isNotEmpty)
          'document_expiries': [
            for (final e in docExpiry.entries)
              {'document_type': e.key.key, 'expiry_date': _isoDate(e.value)},
          ],
      },
      summary: RegistrationSummary(
        role: RegistrationRole.guard,
        lines: [
          if (name != null && name.isNotEmpty)
            (label: isThai ? 'ชื่อ' : 'Name', value: name),
          if (gender != null && gender.isNotEmpty)
            (label: isThai ? 'เพศ' : 'Gender', value: gender),
          if (dateOfBirth != null && dateOfBirth.isNotEmpty)
            (label: isThai ? 'วันเกิด' : 'DOB', value: dateOfBirth),
          if (yearsOfExperience != null)
            (
              label: isThai ? 'ประสบการณ์' : 'Experience',
              value: '$yearsOfExperience ปี'
            ),
          if (bank != null && bank.isNotEmpty)
            (label: isThai ? 'ธนาคาร' : 'Bank', value: bank),
          // MASKED before any local persistence (PDPA).
          (
            label: isThai ? 'เลขบัญชี' : 'Account',
            value: maskAccountNumber(digits)
          ),
          if (addr != null && addr.isNotEmpty)
            (label: isThai ? 'ที่อยู่' : 'Address', value: addr),
          if (ecName != null && ecName.isNotEmpty)
            (label: isThai ? 'ติดต่อฉุกเฉิน' : 'Emergency', value: ecName),
          if (docPaths.isNotEmpty)
            (
              label: isThai ? 'เอกสาร' : 'Documents',
              value: '${docPaths.length}/5'
            ),
        ],
      ),
    );
    // NOTE: docPaths are intentionally NOT uploaded — v2 exposes no document endpoint yet. When
    // it lands, hand them to an upload seam here (best-effort, never blocking the profile submit).
  }

  Future<bool> _submitProfile(
    String path,
    Map<String, dynamic> data, {
    required RegistrationSummary summary,
  }) async {
    // Guard against a double-tap before the busy flag propagates.
    if (state.busy) {
      return false;
    }
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    // Busy BEFORE the async token read so the screen can't launch a second concurrent submit
    // with the same single-use profile_token.
    state = state.copyWith(busy: true, error: null);
    final token =
        _profileToken ?? await ref.read(appStoreProvider).readProfileToken();
    if (token == null) {
      state = state.copyWith(
          busy: false,
          error: isThai
              ? 'หมดเวลา กรุณาลงทะเบียนใหม่'
              : 'Session expired — register again');
      return false;
    }
    try {
      // The single-use profile_token is the Bearer (no session exists yet).
      await ref.read(pguardApiProvider).post(path, data: data, bearer: token);
      // Now that the profile is submitted, persist the pending flag + MASKED summary (prefs,
      // non-sensitive) so a cold start resumes the pending screen with the submitted summary.
      final prefs = ref.read(prefsStoreProvider);
      await prefs.setString(kRegPendingRoleKey, summary.role.wire);
      await prefs.setString(kRegSummaryKey, jsonEncode(summary.toJson()));
      _profileToken = null; // consumed single-use
      state = state.copyWith(busy: false, submitted: summary);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
          busy: false,
          error: isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong');
      return false;
    }
  }

  /// `true` iff "check status" can attempt a login WITHOUT re-prompting the PIN (live flow — the
  /// PIN is still in memory). After a cold start the keepAlive notifier is fresh, so the pending
  /// screen re-prompts the PIN and calls [checkStatusWithPin].
  bool get canCheckSilently => _phone != null && _pin != null;

  /// Attempt `loginWithPin` to see if the pending account is now approved (login succeeds only
  /// once approved; a pending account returns a generic 401 → stays pending). Uses the in-memory
  /// PIN; returns false (no error) if it isn't available.
  Future<bool> checkStatus() async {
    final phone = _phone;
    final pin = _pin;
    if (phone == null || pin == null) return false;
    return _attemptApprovedLogin(phone: phone, pin: pin);
  }

  /// Cold-start "check status": the PIN is re-entered on the pending screen; the phone comes from
  /// secure storage (persisted at register).
  Future<bool> checkStatusWithPin(String pin) async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final phone = _phone ?? await ref.read(appStoreProvider).readPhone();
    if (phone == null) {
      state = state.copyWith(
          error: isThai
              ? 'ไม่พบเบอร์ กรุณาเริ่มใหม่'
              : 'Phone missing — start again');
      return false;
    }
    return _attemptApprovedLogin(phone: phone, pin: pin);
  }

  Future<bool> _attemptApprovedLogin({
    required String phone,
    required String pin,
  }) async {
    state = state.copyWith(busy: true, error: null);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .loginWithPin(phone: phone, pin: pin);
    if (ok) {
      // Approved → now authenticated (loginWithPin flipped the session). Drop pending state.
      await _clearPending();
    }
    // A `false` here means "still pending" (generic 401), NOT an error to surface loudly.
    state = state.copyWith(busy: false);
    return ok;
  }

  Future<void> _clearPending() async {
    final prefs = ref.read(prefsStoreProvider);
    await prefs.remove(kRegPendingRoleKey);
    await prefs.remove(kRegSummaryKey);
    await ref.read(appStoreProvider).clearRegistrationTokens();
    // Also drop the onboarding-resume marker + raw PIN (the flow is complete now).
    await prefs.remove(kRegOnboardingStageKey);
    await ref.read(appStoreProvider).clearOnboardingPin();
    // Drop the raw PIN + phone + tokens from the keepAlive notifier — the flow is complete and the
    // session is now authenticated; don't hold the raw PIN in memory longer than needed.
    _pin = null;
    _phone = null;
    _phoneVerifiedToken = null;
    _profileToken = null;
  }

  /// A prior `POST /auth/register` on this phone already succeeded iff a `profile_token` is still
  /// around (in memory or secure storage) — the pending account exists and the profile step is
  /// next. Used when a re-tap of a role presents a missing/spent phone-verified token (the user
  /// backed out of the profile form): instead of dead-ending or bouncing to phone (losing the
  /// pending registration), resume the flow. Returns [RegisterOutcome.needsProfile] when it
  /// resumes (busy cleared, session re-flagged pending, spent phone-token dropped), else null.
  Future<RegisterOutcome?> _resumeIfAlreadyRegistered() async {
    final store = ref.read(appStoreProvider);
    final existing = _profileToken ?? await store.readProfileToken();
    if (existing == null) return null;
    _profileToken = existing;
    // The phone-verified token (if any) is spent — never present it again.
    _phoneVerifiedToken = null;
    await store.clearPhoneVerifiedToken();
    ref.read(sessionProvider.notifier).onPendingApproval();
    state = state.copyWith(busy: false, error: null);
    return RegisterOutcome.needsProfile;
  }

  /// Drop the onboarding RESUME state only (prefs stage marker + raw PIN in secure storage),
  /// keeping the profile token + phone — used right after a successful 202 register, where the
  /// flow moves on to the profile/pending step.
  Future<void> _clearOnboardingResume() async {
    await ref.read(prefsStoreProvider).remove(kRegOnboardingStageKey);
    await ref.read(appStoreProvider).clearOnboardingPin();
  }

  /// Fully abort an onboarding whose phone-verified token is no longer usable: wipe the resume
  /// marker, the onboarding credentials (raw PIN + tokens), the persisted phone, and all
  /// in-memory fields, so the user restarts cleanly from phone entry.
  Future<void> _abortOnboarding() async {
    final prefs = ref.read(prefsStoreProvider);
    final store = ref.read(appStoreProvider);
    await prefs.remove(kRegOnboardingStageKey);
    await prefs.remove(kRegPendingRoleKey);
    await prefs.remove(kRegSummaryKey);
    await store
        .clearSession(); // drops onboarding PIN + reg tokens + phone (no tokens to lose here)
    _pin = null;
    _phone = null;
    _phoneVerifiedToken = null;
    _profileToken = null;
  }
}

/// Format a date as the wire `YYYY-MM-DD` (the contract's `expiry_date` format). Date-only — no
/// timezone shift (the picker yields a local calendar date and the field is a plain DATE).
String _isoDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}
