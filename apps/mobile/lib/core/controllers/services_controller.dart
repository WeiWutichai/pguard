import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/service_catalog.dart';
import '../providers.dart';

part 'services_controller.g.dart';

/// The admin-defined bookable service catalog from `GET /v1/services` (active services only —
/// the server filters to the active catalog). Fetched once per lifetime; the booking-flow entry
/// screen watches this so a customer always picks from the live catalog, never a hardcoded list.
///
/// Errors / an empty catalog surface as AsyncError / an empty list for the screen to render
/// (retry / empty state). The `{ data: [...] }` envelope is already unwrapped by [PguardApi].
@riverpod
Future<List<ServiceOption>> services(ServicesRef ref) async {
  final data = await ref.read(pguardApiProvider).get('/services');
  return (data as List)
      .whereType<Map<String, dynamic>>()
      .map(ServiceOption.fromJson)
      .toList();
}
