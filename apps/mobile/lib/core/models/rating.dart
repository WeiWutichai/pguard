// Rating-service models (`contracts/openapi/rating.yaml`). Pure (no Flutter) → unit-testable.
//
// `GET /v1/guards/{id}/ratings` → [GuardRatings]: the guard's VISIBLE reviews + the aggregate
// `{ average, count }`. The contract aggregate has NO per-category averages, so the rating screen
// derives them client-side from the returned [reviews] set ([GuardRatings.categoryAverage]).

/// One visible review for a guard (rating-service `Review`).
class Review {
  const Review({
    required this.id,
    required this.guardId,
    required this.overallRating,
    this.punctuality,
    this.professionalism,
    this.communication,
    this.appearance,
    this.reviewText,
    required this.createdAt,
  });

  final String id;
  final String guardId;
  final int overallRating;
  final int? punctuality;
  final int? professionalism;
  final int? communication;
  final int? appearance;
  final String? reviewText;
  final DateTime createdAt;

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: json['id'] as String,
        guardId: json['guard_id'] as String,
        overallRating: (json['overall_rating'] as num).toInt(),
        punctuality: (json['punctuality'] as num?)?.toInt(),
        professionalism: (json['professionalism'] as num?)?.toInt(),
        communication: (json['communication'] as num?)?.toInt(),
        appearance: (json['appearance'] as num?)?.toInt(),
        reviewText: json['review_text'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// A guard's visible ratings + aggregate (`GuardRatings`). `average` is a decimal STRING on the
/// wire ("4.90"); parse defensively. `null`/absent when there are no visible reviews.
class GuardRatings {
  const GuardRatings({
    required this.guardId,
    this.average,
    required this.count,
    required this.reviews,
  });

  final String guardId;
  final String? average;
  final int count;
  final List<Review> reviews;

  factory GuardRatings.fromJson(Map<String, dynamic> json) => GuardRatings(
        guardId: json['guard_id'] as String,
        average: (json['average'] as Object?)?.toString(),
        count: (json['count'] as num?)?.toInt() ?? 0,
        reviews: (json['reviews'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Review.fromJson)
            .toList(),
      );

  /// Overall average parsed for display (null if absent/garbage).
  double? get averageValue =>
      average == null ? null : double.tryParse(average!);

  /// Whether there's a real aggregate to show (never fake a 0.0).
  bool get hasRatings => count > 0 && averageValue != null;

  /// Mean of a category's non-null values across the visible reviews. The contract aggregate
  /// carries no per-category average, so it's derived from the returned set; `null` when no
  /// returned review rated that category.
  double? categoryAverage(int? Function(Review) pick) {
    var sum = 0;
    var n = 0;
    for (final r in reviews) {
      final v = pick(r);
      if (v != null) {
        sum += v;
        n++;
      }
    }
    return n == 0 ? null : sum / n;
  }
}
