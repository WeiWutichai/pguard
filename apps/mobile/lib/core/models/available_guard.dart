// Guard-discovery model — the shape of one item from `GET /v1/available-guards`.
//
// booking owns discovery but neither the guard catalog (profile) nor reviews (rating); the
// endpoint returns the APPROVED guard catalog enriched with each guard's rating summary
// (contracts/openapi/booking.yaml → AvailableGuard). The contract carries NO name / avatar /
// distance / completed-jobs — only the fields below — so the UI renders the merged
// rating-summary the spec calls out: average rating + review count (+ experience).

/// One discoverable guard with their rating summary. Pure (no Flutter) → unit-testable.
class AvailableGuard {
  const AvailableGuard({
    required this.guardId,
    this.yearsOfExperience,
    this.averageRating,
    required this.reviewCount,
  });

  final String guardId;
  final int? yearsOfExperience;

  /// AVG of visible overall ratings as a decimal STRING ("4.50"); null if none/unreachable.
  final String? averageRating;
  final int reviewCount;

  factory AvailableGuard.fromJson(Map<String, dynamic> json) => AvailableGuard(
        guardId: json['guard_id'] as String,
        yearsOfExperience: (json['years_of_experience'] as num?)?.toInt(),
        // Decimal string on the wire; parse defensively.
        averageRating: (json['average_rating'] as Object?)?.toString(),
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      );

  /// The rating parsed for display (null if absent/garbage).
  double? get rating =>
      averageRating == null ? null : double.tryParse(averageRating!);

  /// Whether this guard has a usable rating summary to show.
  bool get hasRating => rating != null && reviewCount > 0;

  /// A short, stable handle derived from the id (the discovery contract has no name).
  String get shortHandle => guardId.length >= 4
      ? guardId.substring(0, 4).toUpperCase()
      : guardId.toUpperCase();
}
