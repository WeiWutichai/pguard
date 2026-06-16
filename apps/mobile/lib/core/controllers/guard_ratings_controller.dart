import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/rating.dart';
import '../providers.dart';

part 'guard_ratings_controller.g.dart';

/// Fetches one guard's visible ratings + aggregate ONCE (`GET /v1/guards/{id}/ratings`) — no
/// polling. Drives the guard's "รีวิวที่ได้รับ" screen and the dashboard rating stat card (both
/// pass the guard's OWN id from the session). Fake-injectable in tests by overriding
/// [pguardApiProvider]. The api client unwraps the `{ success, data }` envelope and returns `data`.
@riverpod
Future<GuardRatings> guardRatings(GuardRatingsRef ref, String guardId) async {
  final data =
      await ref.read(pguardApiProvider).get('/guards/$guardId/ratings');
  return GuardRatings.fromJson(data as Map<String, dynamic>);
}
