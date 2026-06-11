import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/auth_models.dart';
import '../network/api_exception.dart';
import '../network/jwt.dart';
import '../providers.dart';
import 'pin_hasher.dart';
import 'session_controller.dart';

part 'auth_controller.g.dart';

/// The onboarding step the UI is on.
enum AuthStep { phone, otp, pin }

const Object _unset = Object();

/// Cross-screen state for the phone → OTP → PIN/login flow.
class AuthFlowState {
  const AuthFlowState({
    this.step = AuthStep.phone,
    this.phone = '',
    this.challenge,
    this.otpSentAt,
    this.otpRequestCount = 0,
    this.phoneVerifiedToken,
    this.busy = false,
    this.error,
  });

  final AuthStep step;
  final String phone;
  final OtpChallenge? challenge;
  final DateTime? otpSentAt;

  /// How many OTP SMS have been requested this flow (display state for the design's
  /// "พยายาม 1/5 / attempt 1/5" resend counter — the server enforces the real limit).
  final int otpRequestCount;

  /// Single-use phone-verified JWT from `POST /otp/verify`, carried to `POST /auth/register`
  /// (also persisted to secure storage so a backgrounded flow survives). Null until verified.
  final String? phoneVerifiedToken;
  final bool busy;
  final String? error;

  AuthFlowState copyWith({
    AuthStep? step,
    String? phone,
    OtpChallenge? challenge,
    DateTime? otpSentAt,
    int? otpRequestCount,
    String? phoneVerifiedToken,
    bool? busy,
    Object? error = _unset,
  }) {
    return AuthFlowState(
      step: step ?? this.step,
      phone: phone ?? this.phone,
      challenge: challenge ?? this.challenge,
      otpSentAt: otpSentAt ?? this.otpSentAt,
      otpRequestCount: otpRequestCount ?? this.otpRequestCount,
      phoneVerifiedToken: phoneVerifiedToken ?? this.phoneVerifiedToken,
      busy: busy ?? this.busy,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

/// Drives the auth flow against `/v1` (otp + identity services). All network orchestration
/// lives here (not in screens) — screens render [AuthFlowState] and call these methods.
///
/// Phone → OTP → PIN, then the PIN screen hands off to [RegistrationController] (role → register
/// → profile → pending). [loginWithPin] (`POST /auth/login` with `password = SHA-256(pin)`, the
/// same `pin_hash` register stored) is invoked by the registration controller for the 409→login
/// (returning user) and the pending check-status (approved) paths — `phone` is passed explicitly
/// so those callers never depend on this controller's transient state.
@riverpod
class AuthController extends _$AuthController {
  @override
  AuthFlowState build() => const AuthFlowState();

  static final RegExp _thaiPhone = RegExp(r'^0\d{9}$');

  bool isValidPhone(String phone) => _thaiPhone.hasMatch(phone);

  /// PURE display heuristic for the set-PIN strength line ("ความปลอดภัยดี · หลีกเลี่ยงเลขซ้ำ"):
  /// a typed PIN prefix is "weak" when its digits are all identical or form a strictly
  /// ascending/descending run (111111, 123456, 654321). UI feedback only — no storage,
  /// no network; the PIN itself is never rejected for this.
  static bool isWeakPin(String digits) {
    if (digits.length < 2) return false;
    bool run(int step) {
      for (var i = 1; i < digits.length; i++) {
        if (digits.codeUnitAt(i) - digits.codeUnitAt(i - 1) != step) {
          return false;
        }
      }
      return true;
    }

    return run(0) || run(1) || run(-1);
  }

  void setPhone(String phone) =>
      state = state.copyWith(phone: phone, error: null);

  void reset() => state = const AuthFlowState();

  /// `GET /otp/challenge` — fetch the math captcha to gate the OTP request.
  Future<bool> loadChallenge() => _guard(() async {
        final data = await ref.read(pguardApiProvider).get('/otp/challenge');
        state = state.copyWith(
          challenge: OtpChallenge.fromJson(data as Map<String, dynamic>),
        );
        return true;
      });

  /// `POST /otp/request` — solve captcha + send the OTP SMS, then advance to the OTP step.
  Future<bool> sendOtp(String captchaAnswer) async {
    if (!isValidPhone(state.phone)) {
      state =
          state.copyWith(error: 'เบอร์โทรไม่ถูกต้อง / Invalid phone number');
      return false;
    }
    final challenge = state.challenge;
    if (challenge == null) {
      state =
          state.copyWith(error: 'กรุณาโหลดแคปต์ชาใหม่ / Reload the captcha');
      return false;
    }
    return _guard(() async {
      await ref.read(pguardApiProvider).post('/otp/request', data: {
        'phone': state.phone,
        'challenge_id': challenge.challengeId,
        'answer': captchaAnswer,
      });
      state = state.copyWith(
        step: AuthStep.otp,
        otpSentAt: DateTime.now().toUtc(),
        otpRequestCount: state.otpRequestCount + 1,
      );
      return true;
    });
  }

  /// `POST /otp/verify` — confirm the SMS code, then advance to the PIN step. Capture the
  /// single-use `phone_verified_token` (state + secure storage) — it is exchanged at
  /// `POST /auth/register` after the PIN + role are chosen.
  Future<bool> verifyOtp(String code) => _guard(() async {
        final data = await ref.read(pguardApiProvider).post('/otp/verify', data: {
          'phone': state.phone,
          'code': code,
        });
        final token = (data is Map<String, dynamic>)
            ? data['phone_verified_token'] as String?
            : null;
        if (token != null) {
          await ref.read(appStoreProvider).savePhoneVerifiedToken(token);
        }
        state = state.copyWith(step: AuthStep.pin, phoneVerifiedToken: token);
        return true;
      });

  /// `POST /auth/login` with `{ identifier: phone, password: SHA-256(pin) }`. The password is the
  /// SAME `pin_hash` registration submitted (identity Argon2's that hash, so login must present
  /// it — NOT the raw PIN). [phone] is explicit so callers outside the auth flow (the
  /// registration check-status / 409→login paths) don't depend on this controller's transient
  /// state. On success, persist the token pair + phone + local PIN and flip the session to
  /// authenticated (router lands on the role dashboard).
  Future<bool> loginWithPin({required String phone, required String pin}) =>
      _guard(() async {
        final data =
            await ref.read(pguardApiProvider).post('/auth/login', data: {
          'identifier': phone,
          'password': const PinHasher().pinHash(pin),
        });
        final tokens = TokenPair.fromJson(data as Map<String, dynamic>);
        final store = ref.read(appStoreProvider);
        await store.saveTokens(
            access: tokens.accessToken, refresh: tokens.refreshToken);
        // Persist the verified phone (PII, secure storage) so the profile can show it read-only
        // — it is the login identifier and is not returned by any API.
        await store.savePhone(phone);
        // Persist the PIN locally too, so returning cold starts unlock OFFLINE via the lock
        // screen (PinService) without a round-trip. The PIN/hash never leaves the device.
        await ref.read(pinServiceProvider).setup(pin);
        final user = AuthUser(
          userId: Jwt.subject(tokens.accessToken) ?? '',
          role: Jwt.role(tokens.accessToken) ?? 'customer',
        );
        ref.read(sessionProvider.notifier).onLoggedIn(user);
        return true;
      });

  Future<bool> _guard(Future<bool> Function() op) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final ok = await op();
      state = state.copyWith(busy: false);
      return ok;
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
          busy: false, error: 'เกิดข้อผิดพลาด / Something went wrong');
      return false;
    }
  }
}
