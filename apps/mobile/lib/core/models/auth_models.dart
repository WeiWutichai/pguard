// Auth domain models, parsed from the `/v1` ApiResponse `data` payloads. Plain immutable
// classes (no codegen) with manual JSON — small, explicit, testable.

/// The access + refresh token pair from `POST /auth/login` and `POST /auth/refresh`.
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;

  /// Access-token lifetime in seconds (server-reported).
  final int expiresIn;

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      );
}

/// A math captcha challenge from `GET /otp/challenge` (must be solved before requesting OTP).
class OtpChallenge {
  const OtpChallenge({
    required this.challengeId,
    required this.question,
    required this.expiresIn,
  });

  final String challengeId;
  final String question; // e.g. "7 + 5 = ?"
  final int expiresIn;

  factory OtpChallenge.fromJson(Map<String, dynamic> json) => OtpChallenge(
        challengeId: json['challenge_id'] as String,
        question: json['question'] as String,
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      );
}

/// The authenticated principal from `GET /auth/me`.
class AuthUser {
  const AuthUser({required this.userId, required this.role});

  final String userId;
  final String role; // "customer" | "guard" | "admin"

  bool get isCustomer => role == 'customer';
  bool get isGuard => role == 'guard';
  bool get isAdmin => role == 'admin';

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        userId: (json['user_id'] ?? json['sub'] ?? '') as String,
        role: (json['role'] ?? '') as String,
      );
}
