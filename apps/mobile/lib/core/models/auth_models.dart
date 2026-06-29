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

/// The authenticated principal. [role] is the ACTIVE role (from the access token); [roles] is the
/// ENROLLED set (the account's approved roles) — `[role]` for a single-role account, both roles
/// for a dual-role account. The enrolled set comes from login's `available_roles` / `GET /auth/me`'s
/// `roles`; it drives the post-login mode picker and the in-app role switch (one phone = one account
/// that can be BOTH guard + customer).
class AuthUser {
  const AuthUser({
    required this.userId,
    required this.role,
    List<String>? roles,
  }) : roles = roles ?? const [];

  final String userId;
  final String role; // "customer" | "guard" | "admin"

  /// The enrolled/approved roles. Always includes [role]; >1 entry means the account can switch
  /// modes. Never null (an empty list is treated as "just the active role" by [enrolledRoles]).
  final List<String> roles;

  bool get isCustomer => role == 'customer';
  bool get isGuard => role == 'guard';
  bool get isAdmin => role == 'admin';

  /// The enrolled set, guaranteed to contain the active [role] even if the server list was empty
  /// or stale (defensive — the active role is always switchable-back-to).
  List<String> get enrolledRoles =>
      roles.contains(role) ? roles : [role, ...roles];

  /// The account holds more than one approved role → offer the mode picker / switch affordance.
  bool get hasMultipleRoles => enrolledRoles.length > 1;

  bool isEnrolledIn(String r) => enrolledRoles.contains(r);

  /// Copy with a new active [role] (e.g. after a successful switch-role), keeping the enrolled set.
  AuthUser withActiveRole(String role) =>
      AuthUser(userId: userId, role: role, roles: roles);

  /// Copy with an updated enrolled set (e.g. after `GET /auth/me`), keeping the active role.
  AuthUser withRoles(List<String> roles) =>
      AuthUser(userId: userId, role: role, roles: roles);

  /// Normalize a roles JSON array (`available_roles` / `roles`) to a clean, de-duplicated list of
  /// non-empty role strings. Tolerates a missing/non-list value (→ empty).
  static List<String> rolesFromJson(dynamic raw) {
    if (raw is! List) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final e in raw) {
      if (e is String && e.isNotEmpty && seen.add(e)) out.add(e);
    }
    return out;
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        userId: (json['user_id'] ?? json['sub'] ?? '') as String,
        role: (json['role'] ?? '') as String,
        roles: rolesFromJson(json['roles'] ?? json['available_roles']),
      );
}
