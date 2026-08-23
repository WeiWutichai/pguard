// Guard-discovery model — the shape of one item from `GET /v1/available-guards`.
//
// booking owns discovery but neither the guard catalog (profile) nor reviews (rating); the
// endpoint returns the APPROVED guard catalog enriched with each guard's rating summary
// (contracts/openapi/booking.yaml → AvailableGuard), plus — once the BACKEND change lands — the
// guard's `display_name` and `avatar_url` (read by booking from profile's catalog).
//
// [displayName] / [avatarUrl] are OPTIONAL on the wire: the UI shows the real name + photo when
// the field is present and falls back to the id-derived handle / initials avatar when it is not,
// so the client is forward-compatible (works against both the current and the enriched contract).
// See the per-field FLAGs below for the exact backend endpoints that must emit them.

/// One discoverable guard with their rating summary. Pure (no Flutter) → unit-testable.
class AvailableGuard {
  const AvailableGuard({
    required this.guardId,
    this.displayName,
    this.avatarUrl,
    this.yearsOfExperience,
    this.averageRating,
    required this.reviewCount,
    this.hasDocuments,
    this.documents,
    this.distanceMeters,
  });

  final String guardId;

  /// The guard's real display name (profile `full_name`). Null until the BACKEND enriches the
  /// discovery list with it — booking's `/available-guards` aggregator must read it from profile's
  /// `/internal/guards` catalog (`InternalGuard.full_name`) and add `display_name` to the
  /// `AvailableGuard` schema. Falls back to [displayLabel]'s id handle while absent.
  final String? displayName;

  /// A short-lived presigned URL for the guard's profile photo (profile `avatar_key`). Null until
  /// the BACKEND enriches the discovery list with it — booking's aggregator must presign each
  /// guard's avatar (profile already stores `avatar_key`; today only owner/admin can read it via
  /// `GET /profile/guard/{id}/avatar`). Falls back to the initials avatar while absent.
  final String? avatarUrl;

  final int? yearsOfExperience;

  /// AVG of visible overall ratings as a decimal STRING ("4.50"); null if none/unreachable.
  final String? averageRating;
  final int reviewCount;

  /// Whether the guard's five credential documents are on file (profile-derived boolean —
  /// booking's `AvailableGuard.has_documents`). The customer only ever sees THAT documents
  /// exist, never the documents. NULL when the backend didn't say (older backend during a
  /// mixed-version window) — the card renders nothing then, never a false "no documents".
  final bool? hasDocuments;

  /// Per-credential PRESENCE (which credential TYPES the guard has on file) — booking's
  /// `AvailableGuard.documents`, passed through from profile. The customer sees WHICH types exist,
  /// never the files. NULL when the backend didn't say (older backend during a mixed-version
  /// window) — the card renders nothing then, never an all-false "has none".
  final GuardDocuments? documents;

  /// Straight-line distance (meters) from the guard's LIVE position to the booking's meetup point
  /// (C2, booking's `distance_m`). Present ONLY when discovery was called WITH the meetup `lat`/
  /// `lng` AND the guard's live position was known — the server then returns the list already
  /// sorted nearest-first. NULL otherwise; the card shows a distance only when it is meaningful.
  final double? distanceMeters;

  factory AvailableGuard.fromJson(Map<String, dynamic> json) => AvailableGuard(
        guardId: json['guard_id'] as String,
        // Optional enrichment — trim to null so an empty/whitespace name never wins over the
        // id-handle fallback.
        displayName: _nonEmpty(json['display_name'] as Object?),
        avatarUrl: _nonEmpty(json['avatar_url'] as Object?),
        yearsOfExperience: (json['years_of_experience'] as num?)?.toInt(),
        // Decimal string on the wire; parse defensively.
        averageRating: (json['average_rating'] as Object?)?.toString(),
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
        // Tri-state: absent/garbage → null (unknown), never a false "no documents".
        hasDocuments: json['has_documents'] is bool
            ? json['has_documents'] as bool
            : null,
        // Per-type presence; absent → null (unknown, older backend), never an all-false object.
        documents: json['documents'] is Map<String, dynamic>
            ? GuardDocuments.fromJson(json['documents'] as Map<String, dynamic>)
            : null,
        // Nearest-first distance (meters); absent → null (no meetup sent or position unknown).
        distanceMeters: (json['distance_m'] as num?)?.toDouble(),
      );

  static String? _nonEmpty(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// The rating parsed for display (null if absent/garbage).
  double? get rating =>
      averageRating == null ? null : double.tryParse(averageRating!);

  /// Whether this guard has a usable rating summary to show.
  bool get hasRating => rating != null && reviewCount > 0;

  /// A short, stable handle derived from the id — the fallback when discovery carries no name.
  String get shortHandle => guardId.length >= 4
      ? guardId.substring(0, 4).toUpperCase()
      : guardId.toUpperCase();

  /// Whether the discovery list provided a real photo for this guard.
  bool get hasPhoto => avatarUrl != null;

  /// The avatar's initials fallback — the leading grapheme CLUSTER of the real name when present,
  /// otherwise the id handle (so a guard with no photo still gets a stable, legible monogram). The
  /// pure model stays Flutter-free, so the grapheme split is done locally: a base code point plus
  /// any trailing Thai combining marks (above/below vowels + tone marks, U+0E31/U+0E33-0E3A/
  /// U+0E47-0E4E) are kept together as ONE cluster — a leading "บุ" stays "บุ", never a broken "บ".
  String get avatarInitials {
    final name = displayName?.trimLeft();
    if (name != null && name.isNotEmpty) {
      final runes = name.runes.toList();
      final buffer = StringBuffer()..writeCharCode(runes.first);
      for (var i = 1; i < runes.length && _isThaiCombining(runes[i]); i++) {
        buffer.writeCharCode(runes[i]);
      }
      final first = buffer.toString();
      if (first.trim().isNotEmpty) return first.toUpperCase();
    }
    return shortHandle;
  }

  /// Thai combining marks that hang off the preceding base consonant (so they belong to the same
  /// grapheme cluster): mai han-akat, sara am, the below/above vowels, and the tone marks.
  static bool _isThaiCombining(int r) =>
      r == 0x0E31 ||
      (r >= 0x0E33 && r <= 0x0E3A) ||
      (r >= 0x0E47 && r <= 0x0E4E);

  /// The card title: the guard's REAL NAME when discovery provides it, else the id-derived
  /// "เจ้าหน้าที่ #XXXX" handle (so an un-enriched list still renders, just without the name).
  String displayLabel(bool isThai) =>
      displayName ??
      (isThai ? 'เจ้าหน้าที่ #$shortHandle' : 'Guard #$shortHandle');
}

/// Per-credential PRESENCE (has / doesn't-have) for the five customer-relevant credential types.
/// Booleans ONLY — a `true` means the document is on record; the file itself is NEVER exposed to
/// the customer (it stays owner/admin-only). Pure (no Flutter) → unit-testable. The [entries] list
/// gives the UI a stable, ordered `(type, present)` sequence to render as a checklist; the widget
/// maps each `type` key to its localized label.
class GuardDocuments {
  const GuardDocuments({
    required this.idCard,
    required this.securityLicense,
    required this.trainingCert,
    required this.criminalCheck,
    required this.driverLicense,
  });

  final bool idCard;
  final bool securityLicense;
  final bool trainingCert;
  final bool criminalCheck;
  final bool driverLicense;

  factory GuardDocuments.fromJson(Map<String, dynamic> json) => GuardDocuments(
        idCard: json['id_card'] == true,
        securityLicense: json['security_license'] == true,
        trainingCert: json['training_cert'] == true,
        criminalCheck: json['criminal_check'] == true,
        driverLicense: json['driver_license'] == true,
      );

  /// Ordered `(type, present)` entries for a per-type checklist. The `type` is a stable key the
  /// UI maps to a localized label; `present` drives the ✓ / ✗ (has / doesn't-have) marker.
  List<({String type, bool present})> get entries => [
        (type: 'id_card', present: idCard),
        (type: 'security_license', present: securityLicense),
        (type: 'training_cert', present: trainingCert),
        (type: 'criminal_check', present: criminalCheck),
        (type: 'driver_license', present: driverLicense),
      ];
}
