import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/customer_public_profile.dart';
import '../network/api_exception.dart';
import '../providers.dart';

part 'customer_public_profile_controller.g.dart';

/// Resolves the booking CUSTOMER's PUBLIC mini-profile (name) for a given customer id, from
/// `GET /v1/customers/{id}/public` (profile-service `getPublicCustomerProfile`). The MIRROR of
/// [guardPublicProfileProvider] for the other direction: any GUARD may read it — from the job
/// OFFER onwards, per the 2026-07-11 product decision (the old active-booking gate 403'd every
/// unaccepted offer and every finished job in the work history into a `#id` fallback). Lifted
/// into a standalone, watchable provider so any guard screen that knows a `customer_id` can show
/// the customer's REAL NAME instead of a raw id (e.g. the guard job-details sheet's
/// "ลูกค้า / Customer" row, #127).
///
/// Pure enrichment — it DEGRADES to `null` on any API error (404 no profile, 5xx) rather than
/// throwing, so a screen that watches it just falls back to a short `#id` ref and never breaks.
/// One-shot fetch keyed by [customerId]; no timer/polling.
@riverpod
Future<CustomerPublicProfile?> customerPublicProfile(
  CustomerPublicProfileRef ref,
  String customerId,
) async {
  try {
    final data =
        await ref.read(pguardApiProvider).get('/customers/$customerId/public');
    return CustomerPublicProfile.tryParse(data);
  } on ApiException {
    return null;
  }
}
