// The assigned guard's public mini-profile, from `GET /v1/guards/{id}/public` (profile-service
// `PublicGuardProfile`). Shown on the customer live-tracking map to identify the guard. The
// customer may read it only while they have an ACTIVE booking with that guard (server-enforced
// IDOR gate) and only for an approved guard. Pure (no Flutter) → unit-testable.

/// Lean guard identity for the tracking card: name + experience. NEVER bank/address/PII — the
/// contract returns only these fields. No photo (no avatar storage yet → initials/icon fallback).
class GuardPublicProfile {
  const GuardPublicProfile({
    required this.guardId,
    this.fullName,
    this.yearsOfExperience,
  });

  final String guardId;

  /// The guard's display name. `null` when unset on the profile — the UI falls back to a generic
  /// role label rather than inventing a name.
  final String? fullName;

  /// Years of experience (`null` when unset).
  final int? yearsOfExperience;

  factory GuardPublicProfile.fromJson(Map<String, dynamic> json) =>
      GuardPublicProfile(
        guardId: json['user_id'] as String,
        fullName: (json['full_name'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['full_name'] as String).trim(),
        yearsOfExperience: (json['years_of_experience'] as num?)?.toInt(),
      );

  /// Defensive parse; `null` when the body is not a well-formed profile (degrades to no name).
  static GuardPublicProfile? tryParse(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    if (data['user_id'] is! String) return null;
    return GuardPublicProfile.fromJson(data);
  }

  /// Up-to-2-char initials derived from [fullName] for the avatar (Thai or Latin); `null` when
  /// there is no name (the UI shows a shield icon instead — never a fabricated initial).
  String? get initials {
    final name = fullName;
    if (name == null) return null;
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    String head(String s, int n) => s.length <= n ? s : s.substring(0, n);
    if (parts.length == 1) return head(parts.first, 2);
    return '${head(parts.first, 1)}${head(parts[1], 1)}';
  }
}
