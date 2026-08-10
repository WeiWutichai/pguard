// The organization (company) profile that heads a Thai tax invoice — company_name / tax_id /
// address. Admin-owned, org-wide config stored by the profile service (single-row
// `profile.org_settings`, migration profile/0011); the app is a READ-ONLY consumer.
// Pure (no Flutter) → unit-testable.

/// The company block printed on the receipt / ใบกำกับภาษี.
///
/// Every field is nullable because the admin fills the company profile in incrementally. A tax
/// invoice without the seller's legal name + TIN is not a valid tax document, so the receipt asks
/// [isComplete] and, when it is false, SAYS SO instead of printing a blank header that merely
/// looks like a broken document.
class OrgSettings {
  const OrgSettings({this.companyName, this.taxId, this.address});

  /// Legal entity name (e.g. "บริษัท พีการ์ด จำกัด").
  final String? companyName;

  /// Thai TIN — 13 digits (stored as text: leading zeros, future formats).
  final String? taxId;

  /// Registered address.
  final String? address;

  /// Whether the block carries what a ใบกำกับภาษี legally needs from the seller: a name and a
  /// tax id. (The address is required on the real document too, but a missing address alone is
  /// shown as a gap rather than voiding the whole header.)
  bool get isComplete =>
      (companyName?.trim().isNotEmpty ?? false) &&
      (taxId?.trim().isNotEmpty ?? false);

  /// True when nothing at all has been configured (the profile service's "never saved" default).
  bool get isEmpty =>
      (companyName?.trim().isEmpty ?? true) &&
      (taxId?.trim().isEmpty ?? true) &&
      (address?.trim().isEmpty ?? true);

  factory OrgSettings.fromJson(Map<String, dynamic> json) => OrgSettings(
        companyName: _trimToNull(json['company_name'] as Object?),
        taxId: _trimToNull(json['tax_id'] as Object?),
        address: _trimToNull(json['address'] as Object?),
      );

  /// Blank strings are as unset as null — normalize so the UI only null-checks.
  static String? _trimToNull(Object? value) {
    final s = value?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
