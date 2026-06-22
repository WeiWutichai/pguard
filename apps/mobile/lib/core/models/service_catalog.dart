// The customer-facing security-service catalog (entry point of the booking flow).
//
// This is the ADMIN-DEFINED catalog fetched from `GET /v1/services` (active services only) —
// the source of truth for what a customer can book, replacing the old hardcoded categories.
// Each option carries the admin's indicative `base_fee` (฿/hr) and `min_hours`. When the
// customer picks one, the booking sends only its `service_id`; the server prices the booking
// from that catalog service's `base_fee` and enforces its `min_hours`. The CLIENT NEVER SENDS A
// PRICE — `baseFee` here is an ESTIMATE shown pre-booking; the authoritative rate is the created
// booking's server-owned `base_fee`.
//
// Money crosses the wire as a decimal STRING ("230.00") and is parsed to integer **satang** via
// [Money] (1 baht = 100 satang) to avoid float rounding drift (CLAUDE.md money rule).

import 'money.dart';

/// One bookable security service from the admin catalog. Pure (no Flutter) → unit-testable.
class ServiceOption {
  const ServiceOption({
    required this.id,
    required this.nameTh,
    required this.nameEn,
    required this.baseFeeSatang,
    required this.minHours,
  });

  /// Catalog service uuid — the ONLY thing sent on the booking (`service_id`).
  final String id;
  final String nameTh;
  final String nameEn;

  /// Indicative ฿/hr in integer satang (parsed from the decimal `base_fee` string, full
  /// precision). An ESTIMATE for the pre-booking figure — the server owns the real rate.
  final int baseFeeSatang;

  /// Minimum bookable hours the admin set for this service (server-enforced on create).
  final int minHours;

  factory ServiceOption.fromJson(Map<String, dynamic> json) => ServiceOption(
        id: json['id'] as String,
        nameTh: (json['name_th'] as String?) ?? '',
        nameEn: (json['name_en'] as String?) ?? '',
        // Decimal string on the wire ("230.00") → exact satang (never a float).
        baseFeeSatang: Money.satangFromString(json['base_fee'] as String?),
        minHours: (json['min_hours'] as num?)?.toInt() ?? 1,
      );

  /// Locale-aware display name (falls back across languages so a card never renders blank).
  String name(bool isThai) {
    final th = nameTh.trim();
    final en = nameEn.trim();
    if (isThai) return th.isNotEmpty ? th : en;
    return en.isNotEmpty ? en : th;
  }
}
