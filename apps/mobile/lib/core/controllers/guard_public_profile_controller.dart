import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/guard_public_profile.dart';
import '../network/api_exception.dart';
import '../providers.dart';

part 'guard_public_profile_controller.g.dart';

/// Resolves the assigned guard's PUBLIC mini-profile (name + experience) for a given guard id,
/// from `GET /v1/guards/{id}/public` (profile-service `getPublicGuardProfile`). It is the SAME
/// IDOR-gated read the customer live-tracking map already uses (the customer may read it only while
/// they hold an active booking with this guard); here it is lifted into a standalone, watchable
/// provider so any screen that knows a `guard_id` can show the guard's REAL NAME instead of a raw
/// id (e.g. the booking-details sheet's "เจ้าหน้าที่ / Guard" row).
///
/// Pure enrichment — it DEGRADES to `null` on any API error (403 not-on-active-booking, 404 not-yet
/// -approved, 5xx) rather than throwing, so a screen that watches it just falls back to a generic
/// role label / id ref and never breaks. One-shot fetch keyed by [guardId]; no timer/polling.
@riverpod
Future<GuardPublicProfile?> guardPublicProfile(
  GuardPublicProfileRef ref,
  String guardId,
) async {
  try {
    final data = await ref.read(pguardApiProvider).get('/guards/$guardId/public');
    return GuardPublicProfile.tryParse(data);
  } on ApiException {
    return null;
  }
}
