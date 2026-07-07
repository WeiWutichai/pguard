import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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

  /// True while running the ADD-ROLE flow (an already-authenticated user enrolling a SECOND role
  /// via `POST /auth/roles`). The profile-form submit then must NOT write the cold-start pending
  /// markers or flip the session to `pendingApproval` (that would knock the user out of their
  /// CURRENT role) — the new role is simply pending admin approval in the background.
  bool _isAddRole = false;

  static const PinHasher _hasher = PinHasher();

  /// Enter the ADD-ROLE flow (from [RoleSwitchController.enrol]): the logged-in user is enrolling a
  /// NEW [role]; [profileToken] (from `POST /auth/roles`) authorizes the one profile write. The
  /// existing `/auth/register/{role}` profile form drives the rest; on submit the new role is
  /// PENDING approval while the user stays in their current role.
  Future<void> beginAddRole({
    required RegistrationRole role,
    required String profileToken,
  }) async {
    _isAddRole = true;
    _profileToken = profileToken;
    _phone = null;
    _phoneVerifiedToken = null;
    _pin = null;
    // Persist (secure) so a backgrounded add-role flow survives a brief app restart and the profile
    // submit can still present the token — mirrors how `register()` stashes its profile_token.
    await ref.read(appStoreProvider).saveProfileToken(profileToken);
    state = RegistrationState(role: role);
  }

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
    _isAddRole = false; // a fresh first-role registration, not an add-role
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

  /// `POST /auth/register/add-role { phone_verified_token, role }` — ADD a SECOND pending role to
  /// a still-pending account (the "register both roles" flow). [role] is the OTHER role (the app
  /// picks the opposite of the account's current role). The FRESH `phone_verified_token` from the
  /// just-completed OTP re-verify authorizes it (a pending account has no access token, and the
  /// original register profile_token is spent). On **202** → stash the returned `profile_token` for
  /// the new role and return [RegisterOutcome.needsProfile] so the caller pushes that role's profile
  /// form; the session is left as-is (still `pendingApproval`). On **409** the account already holds
  /// that role. Never sets a PIN (the account has one).
  Future<RegisterOutcome> addSecondRoleWhilePending(
      RegistrationRole role) async {
    if (state.busy) return RegisterOutcome.error;
    state = state.copyWith(busy: true, error: null, role: role);
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final store = ref.read(appStoreProvider);
    final pvt = ref.read(authControllerProvider).phoneVerifiedToken ??
        await store.readPhoneVerifiedToken();
    if (pvt == null) {
      state = state.copyWith(
          busy: false,
          error: isThai
              ? 'การยืนยันหมดอายุ กรุณาขอ OTP ใหม่'
              : 'Verification expired — request a new OTP');
      return RegisterOutcome.error;
    }
    try {
      final data = await ref
          .read(pguardApiProvider)
          .post('/auth/register/add-role', data: {
        'phone_verified_token': pvt,
        'role': role.wire,
      });
      final profileToken = (data is Map<String, dynamic>)
          ? data['profile_token'] as String?
          : null;
      if (profileToken != null) {
        _profileToken = profileToken;
        await store.saveProfileToken(profileToken);
      }
      // The OTP token is now consumed — drop it so a back-out can't re-present a spent token.
      _phoneVerifiedToken = null;
      await store.clearPhoneVerifiedToken();
      // Session is already `pendingApproval` — leave it. The profile submit below persists the
      // (new-role) pending summary and lands back on the pending screen.
      state = state.copyWith(busy: false);
      return RegisterOutcome.needsProfile;
    } on ApiException catch (e) {
      // 409 ROLE_ALREADY_HELD — the account already has this role (current or approved).
      final msg = e.statusCode == 409
          ? (isThai
              ? 'บัญชีนี้มีบทบาทนี้อยู่แล้ว'
              : 'This account already has that role')
          : e.message;
      state = state.copyWith(busy: false, error: msg);
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
  }) async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final name = fullName?.trim();
    final addr = address.trim();
    final company = companyName?.trim();
    final mail = email?.trim();
    final phone = contactPhone?.trim();
    return await _submitProfile(
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
        ) !=
        null;
  }

  /// `POST /profile/guard` with the `profile_token`. The FULL account number is sent to the
  /// backend; the locally-persisted summary masks it to last-4. `docPaths` are the real-picker
  /// document images — uploaded right after the submit (via [_uploadGuardDocs], using the
  /// `doc_upload_token` the submit returns) so an admin can review them BEFORE approving.
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
    // The passbook photo is captured separately on the form (its own box, no expiry, not a
    // [GuardDocKind]); it uploads under document_type `passbook_photo`.
    String? passbookPath,
  }) async {
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
    final submitData = await _submitProfile(
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
    if (submitData == null) return false;
    // Upload the attached credential images with the registration `doc_upload_token` so an admin
    // can review them BEFORE approving. Best-effort + per-doc: the profile + expiry are already
    // saved, so one failed image never aborts the others or the registration (the guard can
    // re-upload from "My documents" once approved). Keep `busy` ON across the uploads so the
    // CTA can't re-fire (and re-POST the now-spent profile_token) mid-upload.
    // document_type → image path: the 5 credential kinds PLUS the separately-captured passbook
    // (which has no [GuardDocKind]). Without the passbook here it was captured but never uploaded.
    final uploads = <String, String>{
      for (final e in docPaths.entries) e.key.key: e.value,
      if (passbookPath != null && passbookPath.isNotEmpty)
        'passbook_photo': passbookPath,
    };
    if (uploads.isNotEmpty) {
      state = state.copyWith(busy: true);
      await _uploadGuardDocs(submitData, uploads);
      state = state.copyWith(busy: false);
    }
    return true;
  }

  /// Upload each freshly-picked credential image to its own-only doc endpoint using the
  /// registration `doc_upload_token` (and `user_id`) returned by the profile submit. MIME is
  /// declared from the file's magic bytes so the server's content check always matches.
  Future<void> _uploadGuardDocs(
    Map<String, dynamic> submitData,
    Map<String, String> uploads,
  ) async {
    if (uploads.isEmpty) return;
    final token = submitData['doc_upload_token'] as String?;
    final userId = submitData['user_id'] as String?;
    if (token == null || userId == null) return;
    final api = ref.read(pguardApiProvider);
    for (final entry in uploads.entries) {
      try {
        final mime =
            _detectImageMime(await _readHead(entry.value, 12)) ?? 'image/jpeg';
        final form = FormData.fromMap({
          'document_type': entry.key,
          'file': await MultipartFile.fromFile(
            entry.value,
            filename: entry.value.split('/').last,
            contentType: DioMediaType.parse(mime),
          ),
        });
        await api.post('/profile/guard/$userId/documents',
            data: form, bearer: token);
      } catch (e) {
        // best-effort per document — never block the rest or the (already-saved) registration.
        // Breadcrumb so a silently-lost upload (e.g. expired token) is observable in the field;
        // the guard can re-upload from "My documents" once approved.
        debugPrint('guard doc upload (${entry.key}) failed: $e');
      }
    }
  }

  /// First [n] bytes of [path] (a magic-byte sniff) without loading the whole file.
  static Future<List<int>> _readHead(String path, int n) async {
    final f = await File(path).open();
    try {
      return await f.read(n);
    } finally {
      await f.close();
    }
  }

  /// Image MIME from magic bytes — mirrors the server's detector (JPEG/PNG/WEBP). null otherwise.
  /// (Same logic as the guard-documents/avatar controllers; a shared image-upload util is a small
  /// follow-up — tracked in PROGRESS.)
  static String? _detectImageMime(List<int> b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  /// POST a profile with the single-use `profile_token`. Returns the server's response `data`
  /// (the masked profile; for a guard it ALSO carries `user_id` + `doc_upload_token`) on success,
  /// or `null` on failure.
  Future<Map<String, dynamic>?> _submitProfile(
    String path,
    Map<String, dynamic> data, {
    required RegistrationSummary summary,
  }) async {
    // Guard against a double-tap before the busy flag propagates.
    if (state.busy) {
      return null;
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
      return null;
    }
    // The token's purpose MUST match the role being submitted. A leftover token from the other
    // role's registration (e.g. a stale guard token presented to /profile/customer) is rejected
    // server-side as a wrong-purpose token → the access-token fallback then fails with a confusing
    // "missing field `role`". Fail fast with a clear prompt and drop the stale token so the retry
    // starts clean.
    final tokenRole = _roleOfProfileToken(token);
    if (tokenRole != null && tokenRole != summary.role) {
      await ref.read(appStoreProvider).clearRegistrationTokens();
      _profileToken = null;
      state = state.copyWith(
          busy: false,
          error: isThai
              ? 'เซสชันลงทะเบียนไม่ตรงกับบทบาท กรุณาลงทะเบียนใหม่'
              : 'Registration session mismatch — please register again');
      return null;
    }
    try {
      // The single-use profile_token is the Bearer. For a first-role registration there is no
      // session yet; for an ADD-ROLE the user IS authenticated but the purpose-scoped token (not the
      // session token) still authorizes this one write, so `bearer:` is correct in both cases.
      final resp = await ref
          .read(pguardApiProvider)
          .post(path, data: data, bearer: token);
      // First-role registration: persist the pending flag + MASKED summary (prefs, non-sensitive) so
      // a cold start resumes the pending screen with the submitted summary.
      // ADD-ROLE: the user stays in their CURRENT (approved) role — the new role is just pending in
      // the background. Writing the cold-start pending markers here would TRAP them on the pending
      // screen on the next cold start, so skip them; just surface the submitted confirmation.
      if (!_isAddRole) {
        final prefs = ref.read(prefsStoreProvider);
        await prefs.setString(kRegPendingRoleKey, summary.role.wire);
        await prefs.setString(kRegSummaryKey, jsonEncode(summary.toJson()));
      }
      _profileToken = null; // consumed single-use
      _isAddRole = false; // the add-role write is done
      state = state.copyWith(busy: false, submitted: summary);
      return resp is Map<String, dynamic> ? resp : <String, dynamic>{};
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return null;
    } catch (_) {
      state = state.copyWith(
          busy: false,
          error: isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong');
      return null;
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
  /// The role a persisted `profile_token` was minted for, decoded from its JWT `purpose` claim
  /// (`guard_profile` / `customer_profile`); null when malformed/unrecognised. Used to make sure a
  /// token from one role's registration is never presented to the OTHER role's profile route — the
  /// server rejects a wrong-purpose token and the access-token fallback then fails with a confusing
  /// "missing field `role`".
  RegistrationRole? _roleOfProfileToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
      switch (payload['purpose']) {
        case 'guard_profile':
          return RegistrationRole.guard;
        case 'customer_profile':
          return RegistrationRole.customer;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<RegisterOutcome?> _resumeIfAlreadyRegistered() async {
    final store = ref.read(appStoreProvider);
    final existing = _profileToken ?? await store.readProfileToken();
    if (existing == null) return null;
    // Switching roles after a prior register (the single-use phone-verify token is already spent):
    // the leftover token is for the OTHER role and must NOT be carried into this role's profile form
    // (the server rejects a wrong-purpose token). Re-issue a correct-role profile_token via the
    // still-valid one — NO re-OTP — so "back → pick another role" just works within its lifetime.
    // On failure (e.g. the token finally expired) drop it and fall through to a clean restart.
    final tokenRole = _roleOfProfileToken(existing);
    if (state.role != null && tokenRole != null && tokenRole != state.role) {
      final switched = await _reissueProfileTokenForRole(existing, state.role!);
      if (switched != null) return switched;
      await store.clearRegistrationTokens();
      _profileToken = null;
      return null;
    }
    _profileToken = existing;
    // The phone-verified token (if any) is spent — never present it again.
    _phoneVerifiedToken = null;
    await store.clearPhoneVerifiedToken();
    ref.read(sessionProvider.notifier).onPendingApproval();
    state = state.copyWith(busy: false, error: null);
    return RegisterOutcome.needsProfile;
  }

  /// Switch the pending account to [role] WITHOUT re-OTP: exchange the still-valid (but wrong-role)
  /// [oldToken] for a fresh correct-role `profile_token` via `POST /auth/register/reissue` (Bearer =
  /// the old token). Identity updates the pending account's role, consumes the old token, and mints
  /// the new one. Returns [RegisterOutcome.needsProfile] on success, else null (caller restarts).
  Future<RegisterOutcome?> _reissueProfileTokenForRole(
      String oldToken, RegistrationRole role) async {
    try {
      final data = await ref.read(pguardApiProvider).post(
            '/auth/register/reissue',
            data: {'role': role.wire},
            bearer: oldToken,
          );
      final newToken = (data is Map<String, dynamic>)
          ? data['profile_token'] as String?
          : null;
      if (newToken == null) return null;
      _profileToken = newToken;
      await ref.read(appStoreProvider).saveProfileToken(newToken);
      ref.read(sessionProvider.notifier).onPendingApproval();
      state = state.copyWith(busy: false, error: null);
      return RegisterOutcome.needsProfile;
    } on ApiException catch (_) {
      return null;
    }
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
