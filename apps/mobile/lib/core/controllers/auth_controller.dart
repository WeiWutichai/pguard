import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/auth_models.dart';
import '../network/api_exception.dart';
import '../network/jwt.dart';
import '../providers.dart';
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
    this.busy = false,
    this.error,
  });

  final AuthStep step;
  final String phone;
  final OtpChallenge? challenge;
  final DateTime? otpSentAt;
  final bool busy;
  final String? error;

  AuthFlowState copyWith({
    AuthStep? step,
    String? phone,
    OtpChallenge? challenge,
    DateTime? otpSentAt,
    bool? busy,
    Object? error = _unset,
  }) {
    return AuthFlowState(
      step: step ?? this.step,
      phone: phone ?? this.phone,
      challenge: challenge ?? this.challenge,
      otpSentAt: otpSentAt ?? this.otpSentAt,
      busy: busy ?? this.busy,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

/// Drives the auth flow against `/v1` (otp + identity services). All network orchestration
/// lives here (not in screens) — screens render [AuthFlowState] and call these methods.
///
/// Final step uses the v1 "PIN doubles as the password" pattern: `POST /auth/login` with
/// `{ identifier: phone, password: pin }`. (Registration that consumes the phone_verified
/// token is future backend work — see the spec; the OTP steps already hit the live service.)
@riverpod
class AuthController extends _$AuthController {
  @override
  AuthFlowState build() => const AuthFlowState();

  static final RegExp _thaiPhone = RegExp(r'^0\d{9}$');

  bool isValidPhone(String phone) => _thaiPhone.hasMatch(phone);

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
      state =
          state.copyWith(step: AuthStep.otp, otpSentAt: DateTime.now().toUtc());
      return true;
    });
  }

  /// `POST /otp/verify` — confirm the SMS code, then advance to the PIN step. The
  /// phone_verified_token in the response is reserved for the future registration endpoint.
  Future<bool> verifyOtp(String code) => _guard(() async {
        await ref.read(pguardApiProvider).post('/otp/verify', data: {
          'phone': state.phone,
          'code': code,
        });
        state = state.copyWith(step: AuthStep.pin);
        return true;
      });

  /// `POST /auth/login` with `{ identifier: phone, password: pin }`. On success, persist the
  /// token pair and flip the session to authenticated (router lands on the role dashboard).
  Future<bool> loginWithPin(String pin) => _guard(() async {
        final data =
            await ref.read(pguardApiProvider).post('/auth/login', data: {
          'identifier': state.phone,
          'password': pin,
        });
        final tokens = TokenPair.fromJson(data as Map<String, dynamic>);
        await ref.read(appStoreProvider).saveTokens(
            access: tokens.accessToken, refresh: tokens.refreshToken);
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
