// The customer-facing security-service catalog (entry point of the booking flow).
//
// IMPORTANT — this is a PRESENTATION catalog, not a backend resource. v2's booking contract has
// no `service_type` field and a single SERVER-OWNED `base_fee` (there is no `/v1/pricing/services`
// endpoint). These categories frame the UX and choose copy/iconography; the selected service is
// carried in the draft for display only. [indicativeHourlySatang] is an ESTIMATE shown
// pre-booking — the AUTHORITATIVE rate is the created booking's `base_fee`.
//
// Labels/estimates mirror the hi-fi design (`Mobile - Customer App.html` service-select screen).

/// A security-service category shown on the selection screen.
enum SecurityService {
  village(
    'village',
    'หมู่บ้าน',
    'Village',
    'รปภ. ประจำจุด ตรวจรอบ',
    'Posted guard, patrols',
    23000,
  ),
  condo(
    'condo',
    'คอนโด',
    'Condo',
    'คัดกรองผู้เข้า-ออก',
    'Entry screening',
    25000,
  ),
  factory(
    'factory',
    'โรงงาน',
    'Factory',
    'พื้นที่กว้าง ตรวจยานพาหนะ',
    'Large site, vehicles',
    28000,
  ),
  other(
    'other',
    'อื่นๆ',
    'Other',
    'อีเวนต์ งานพิเศษ',
    'Events, custom',
    null,
  );

  const SecurityService(
    this.id,
    this.labelTh,
    this.labelEn,
    this.descTh,
    this.descEn,
    this.indicativeHourlySatang,
  );

  /// Stable identifier (also the design's icon key).
  final String id;
  final String labelTh;
  final String labelEn;
  final String descTh;
  final String descEn;

  /// Indicative ฿/hr estimate in satang for the pre-booking estimate; `null` = custom quote.
  final int? indicativeHourlySatang;

  static SecurityService? tryParse(String? id) {
    if (id == null) return null;
    for (final s in SecurityService.values) {
      if (s.id == id) return s;
    }
    return null;
  }
}
