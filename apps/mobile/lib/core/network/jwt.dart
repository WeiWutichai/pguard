import 'dart:convert';

/// Minimal, UNVERIFIED JWT claim reader. The client never trusts these claims for authz —
/// it only needs `exp` to decide when to refresh proactively (the server re-validates every
/// token). Pure + dependency-free so it is unit-testable.
class Jwt {
  const Jwt._();

  /// Decode the JWT payload (middle segment) to a claims map, or `null` if malformed.
  static Map<String, dynamic>? decodeClaims(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// The token's `exp` as a UTC [DateTime], or `null` if absent/malformed.
  static DateTime? expiry(String token) {
    final exp = decodeClaims(token)?['exp'];
    if (exp is! int && exp is! double) return null;
    final seconds = (exp as num).toInt();
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  /// `true` if the token is missing/expired, or expires within [leeway] of [now].
  /// [now] is injectable so the logic is deterministic in tests.
  static bool isExpiredOrExpiring(
    String token, {
    required Duration leeway,
    DateTime? now,
  }) {
    final exp = expiry(token);
    if (exp == null) return true;
    final reference = (now ?? DateTime.now().toUtc()).add(leeway);
    return !exp.isAfter(reference);
  }

  /// The `role` claim (customer/guard/admin), or `null`.
  static String? role(String token) => decodeClaims(token)?['role'] as String?;

  /// The `sub` (user id) claim, or `null`.
  static String? subject(String token) =>
      decodeClaims(token)?['sub'] as String?;
}
