import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/org_settings.dart';
import '../providers.dart';

part 'org_settings_controller.g.dart';

/// The org (company) profile that heads the tax invoice — `company_name` / `tax_id` / `address`,
/// admin-owned config stored by the profile service (`profile.org_settings`).
///
/// BEST-EFFORT BY DESIGN: any failure (not configured, the route not reachable for this role, no
/// network) resolves to `null`, and the receipt then states plainly that the company details are
/// not set up rather than rendering an empty letterhead that reads as a broken document. A receipt
/// must never fail to open because a company field is missing.
///
/// BACKEND DEPENDENCY: the only route that exists today is `GET /v1/admin/org-settings`
/// (`contracts/openapi/profile.yaml`, role=admin), which a customer cannot read. This provider
/// reads the customer-visible `GET /v1/org-settings` the receipt needs; until the profile service
/// exposes it, the call 404s and the receipt shows its honest "company details not configured"
/// state.
@riverpod
Future<OrgSettings?> orgSettings(OrgSettingsRef ref) async {
  try {
    final data = await ref.read(pguardApiProvider).get('/org-settings');
    if (data is! Map<String, dynamic>) return null;
    final settings = OrgSettings.fromJson(data);
    return settings.isEmpty ? null : settings;
  } catch (_) {
    // Never surface as an error: the receipt degrades to the "not configured" header.
    return null;
  }
}
