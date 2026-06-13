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

  /// Snapshot the auth-flow credentials once the PIN is set (called from the PIN screen). The
  /// `phone_verified_token` also lives in secure storage as a fallback for a backgrounded flow.
  void beginFromAuth({
    required String phone,
    String? phoneVerifiedToken,
    required String pin,
  }) {
    _phone = phone;
    _phoneVerifiedToken = phoneVerifiedToken;
    _pin = pin;
    state =
        const RegistrationState(); // fresh flow (clears any stale role/error/summary)
  }

  void selectRole(RegistrationRole role) =>
      state = state.copyWith(role: role, error: null);

  /// `POST /auth/register { phone_verified_token, role, pin_hash }`. On **202** → stash the
  /// `profile_token`, persist the pending flag, flip the session to **pendingApproval** (NO
  /// tokens). On **409** → `loginWithPin` (the phone already exists in a non-pending state).
  Future<RegisterOutcome> register() async {
    // Guard the brief pre-state-update window against a double-tap.
    if (state.busy) {
      return RegisterOutcome.error;
    }
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final role = state.role;
    final store = ref.read(appStoreProvider);
    final pvt = _phoneVerifiedToken ?? await store.readPhoneVerifiedToken();
    final pin = _pin;
    final phone = _phone;
    if (role == null || pvt == null || pin == null || phone == null) {
      state = state.copyWith(
          busy: false,
          error: isThai
              ? 'หมดเวลายืนยัน กรุณาเริ่มใหม่'
              : 'Verification expired — start again');
      return RegisterOutcome.error;
    }

    state = state.copyWith(busy: true, error: null);
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
      // The phone-verified token is now consumed; the next OTP cycle would mint a fresh one.
      _phoneVerifiedToken = null;
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
  /// length); company/email don't exist in the v2 contract and are omitted.
  Future<bool> submitCustomerProfile({
    String? fullName,
    required String address,
  }) {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final name = fullName?.trim();
    final addr = address.trim();
    return _submitProfile(
      '/profile/customer',
      {
        if (name != null && name.isNotEmpty) 'full_name': name,
        'address': addr,
      },
      summary: RegistrationSummary(
        role: RegistrationRole.customer,
        lines: [
          if (name != null && name.isNotEmpty)
            (label: isThai ? 'ชื่อ' : 'Name', value: name),
          (label: isThai ? 'ที่อยู่' : 'Address', value: addr),
        ],
      ),
    );
  }

  /// `POST /profile/guard` with the `profile_token`. The FULL account number is sent to the
  /// backend; the locally-persisted summary masks it to last-4. `docPaths` are the real-picker
  /// document images — captured + validated client-side and held for the future upload endpoint
  /// (v2 `profile.yaml` has no document-upload route yet; see [GuardDocKind]).
  Future<bool> submitGuardProfile({
    String? gender,
    String? dateOfBirth,
    int? yearsOfExperience,
    String? previousWorkplace,
    String? bankName,
    required String accountNumber,
    String? accountName,
    Map<GuardDocKind, String> docPaths = const {},
  }) {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final digits = accountNumber.replaceAll(RegExp(r'\D'), '');
    final bank = bankName?.trim();
    final acctName = accountName?.trim();
    final workplace = previousWorkplace?.trim();
    return _submitProfile(
      '/profile/guard',
      {
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
      },
      summary: RegistrationSummary(
        role: RegistrationRole.guard,
        lines: [
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
    // Drop the raw PIN + phone + tokens from the keepAlive notifier — the flow is complete and the
    // session is now authenticated; don't hold the raw PIN in memory longer than needed.
    _pin = null;
    _phone = null;
    _phoneVerifiedToken = null;
    _profileToken = null;
  }
}
