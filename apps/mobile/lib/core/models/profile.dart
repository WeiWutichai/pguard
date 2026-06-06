// Profile domain model — the caller's own profile, merged from two endpoints:
//   GET /v1/auth/me      → { user_id, role }                 (identity; minimal)
//   GET /v1/profile/me   → MyGuardProfile | MyCustomerProfile (profile; oneOf by `kind`)
// Pure (no Flutter) → unit-testable.
//
// NOTE (v2 contract reality): identity exposes NO name/phone/email/avatar — only user_id+role.
// The customer profile has full_name + address; the guard profile has gender/dob/experience/
// workplace/bank(masked)/approval_status but NO name. Phone is the login identifier and is
// not returned by any endpoint — it is read from secure storage (persisted at login).

/// Guard onboarding/approval state.
enum ApprovalStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const ApprovalStatus(this.wire);

  final String wire;

  static ApprovalStatus? tryParse(String? value) {
    for (final s in ApprovalStatus.values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// The caller's unified profile.
class UserProfile {
  const UserProfile({
    required this.userId,
    required this.role,
    required this.kind,
    this.phone,
    this.fullName,
    this.address,
    this.gender,
    this.dateOfBirth,
    this.yearsOfExperience,
    this.previousWorkplace,
    this.bankName,
    this.accountNumberMasked,
    this.accountName,
    this.approvalStatus,
  });

  final String userId;
  final String role; // "customer" | "guard" | "admin" (from /auth/me)
  final String kind; // "customer" | "guard" (profile discriminator; inferred from role if no profile yet)
  final String? phone; // login identifier, from secure storage (read-only)

  // customer
  final String? fullName;
  final String? address;

  // guard
  final String? gender;
  final String? dateOfBirth;
  final int? yearsOfExperience;
  final String? previousWorkplace;
  final String? bankName;
  final String? accountNumberMasked; // server masks to last 4
  final String? accountName;
  final ApprovalStatus? approvalStatus;

  bool get isGuard => kind == 'guard';
  bool get isCustomer => kind == 'customer';

  /// Best display name from what the contract actually provides (no name on identity/guard).
  String get displayName {
    if (fullName != null && fullName!.isNotEmpty) return fullName!;
    if (accountName != null && accountName!.isNotEmpty) return accountName!;
    return isGuard ? 'เจ้าหน้าที่' : 'ลูกค้า';
  }

  /// Initials for the avatar fallback (no avatar endpoint exists in v2).
  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// Merge the identity `/auth/me` payload + the profile `/profile/me` payload (+ local phone).
  factory UserProfile.from({
    required Map<String, dynamic> me,
    Map<String, dynamic>? profile,
    String? phone,
  }) {
    final role = (me['role'] as String?) ?? '';
    final userId = (me['user_id'] as String?) ?? (me['sub'] as String?) ?? '';
    final kind = (profile?['kind'] as String?) ?? role;
    return UserProfile(
      userId: userId,
      role: role,
      kind: kind,
      phone: phone,
      fullName: profile?['full_name'] as String?,
      address: profile?['address'] as String?,
      gender: profile?['gender'] as String?,
      dateOfBirth: profile?['date_of_birth'] as String?,
      yearsOfExperience: (profile?['years_of_experience'] as num?)?.toInt(),
      previousWorkplace: profile?['previous_workplace'] as String?,
      bankName: profile?['bank_name'] as String?,
      accountNumberMasked: profile?['account_number'] as String?,
      accountName: profile?['account_name'] as String?,
      approvalStatus: ApprovalStatus.tryParse(profile?['approval_status'] as String?),
    );
  }

  UserProfile copyWith({
    String? fullName,
    String? address,
    String? gender,
    String? dateOfBirth,
    int? yearsOfExperience,
    String? previousWorkplace,
    String? bankName,
    String? accountNumberMasked,
    String? accountName,
  }) =>
      UserProfile(
        userId: userId,
        role: role,
        kind: kind,
        phone: phone,
        fullName: fullName ?? this.fullName,
        address: address ?? this.address,
        gender: gender ?? this.gender,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        yearsOfExperience: yearsOfExperience ?? this.yearsOfExperience,
        previousWorkplace: previousWorkplace ?? this.previousWorkplace,
        bankName: bankName ?? this.bankName,
        accountNumberMasked: accountNumberMasked ?? this.accountNumberMasked,
        accountName: accountName ?? this.accountName,
        approvalStatus: approvalStatus,
      );
}
