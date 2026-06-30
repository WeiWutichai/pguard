// The booking customer's public MINI-profile, from `GET /v1/customers/{id}/public` (profile-service
// `PublicCustomerProfile`). Shown on the GUARD's job sheet so the guard sees the customer's REAL
// NAME instead of a raw id. The MIRROR of [GuardPublicProfile] for the other direction: the guard
// may read it only while ASSIGNED to an active booking with that customer (server-enforced IDOR
// gate). Pure (no Flutter) → unit-testable.

/// Lean customer identity for the guard's job sheet: name + photo. NEVER address/company/email/phone
/// — the contract returns only `{ user_id, full_name, avatar_url }`. [avatarUrl] is a short-lived
/// presigned URL (or `null` when the customer set no photo → initials fallback).
class CustomerPublicProfile {
  const CustomerPublicProfile({
    required this.customerId,
    this.fullName,
    this.avatarUrl,
  });

  final String customerId;

  /// The customer's display name. `null`/empty when unset on the profile — the UI falls back to a
  /// short `#id` ref rather than inventing a name.
  final String? fullName;

  /// Presigned GET URL for the customer's photo (expires ~1h), `null` when unset → initials.
  final String? avatarUrl;

  factory CustomerPublicProfile.fromJson(Map<String, dynamic> json) =>
      CustomerPublicProfile(
        customerId: json['user_id'] as String,
        fullName: (json['full_name'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['full_name'] as String).trim(),
        avatarUrl: (json['avatar_url'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['avatar_url'] as String).trim(),
      );

  /// Defensive parse; `null` when the body is not a well-formed profile (degrades to no name).
  static CustomerPublicProfile? tryParse(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    if (data['user_id'] is! String) return null;
    return CustomerPublicProfile.fromJson(data);
  }

  /// Up-to-2-char initials derived from [fullName] for the avatar monogram; `null` when no name.
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
