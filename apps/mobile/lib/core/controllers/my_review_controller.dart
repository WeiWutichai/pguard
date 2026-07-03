import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/rating.dart';
import '../network/api_exception.dart';
import '../providers.dart';

part 'my_review_controller.g.dart';

/// The customer's OWN review of a completed booking (`GET /v1/assignments/{id}/review`) — the
/// [Review] when they have already rated, or `null` when they have not (the server answers 404).
///
/// Drives the "rate the guard" gate on a completed booking: once a review exists the entry shows a
/// "rated" state instead of re-opening the rating form, so the customer never re-submits into the
/// server's one-per-assignment 409 dead-end. The 409 remains the authoritative backstop — this only
/// surfaces "already rated" up front. Invalidate this provider after a successful submit so the gate
/// flips without a manual reload.
@riverpod
Future<Review?> myReview(MyReviewRef ref, String bookingId) async {
  try {
    final data =
        await ref.read(pguardApiProvider).get('/assignments/$bookingId/review');
    return Review.fromJson(data as Map<String, dynamic>);
  } on ApiException catch (e) {
    // 404 = the caller has not reviewed this booking (a normal "not rated yet" state, not an error).
    if (e.statusCode == 404) return null;
    rethrow;
  }
}
