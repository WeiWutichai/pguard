// Pure (no Flutter) value types + label catalogs for the richer booking form's extra detail
// fields — the security-equipment and add-on-service checkbox groups, plus the free-text "extra
// details" note.
//
// The v2 `POST /v1/bookings` contract carries ONLY a free-text `address` (no notes/equipment
// columns) — so these extras are FOLDED INTO the `address` string as labelled lines by
// [composeAddress]. No backend change, no new fields, no price effect: equipment/add-ons are
// informational for the guard/admin who read the booking address. Kept pure so the compose +
// label logic is unit-testable without widgets.

/// A booking extra (one equipment item or one add-on service): a stable wire [id] plus its
/// bilingual label. The id never crosses the wire (extras are folded into `address` text) — it is
/// the selection key in the form's `Set<String>`.
class BookingExtra {
  const BookingExtra({
    required this.id,
    required this.labelTh,
    required this.labelEn,
  });

  final String id;
  final String labelTh;
  final String labelEn;

  /// Locale-aware label (the text rendered on the checkbox AND folded into the address).
  String label(bool isThai) => isThai ? labelTh : labelEn;
}

/// อุปกรณ์รักษาความปลอดภัย / security equipment the customer can request. Display order is the
/// checkbox order. Folded into the booking address; no price effect.
const List<BookingExtra> kSecurityEquipment = [
  BookingExtra(id: 'flashlight', labelTh: 'ไฟฉาย', labelEn: 'Flashlight'),
  BookingExtra(id: 'handcuffs', labelTh: 'กุญแจมือ', labelEn: 'Handcuffs'),
  BookingExtra(
      id: 'baton', labelTh: 'กระบอง/กระบองไฟฟ้า', labelEn: 'Baton/stun baton'),
  BookingExtra(
      id: 'uniform', labelTh: 'ชุดยูนิฟอร์ม รปภ.', labelEn: 'Guard uniform'),
  BookingExtra(
      id: 'body_armour',
      labelTh: 'เสื้อเกราะ/เสื้อกันกระสุน',
      labelEn: 'Body armour'),
  BookingExtra(id: 'other', labelTh: 'อื่นๆ', labelEn: 'Other'),
];

/// บริการเพิ่มเติม / add-on services. Folded into the booking address; no price effect.
const List<BookingExtra> kAddOnServices = [
  BookingExtra(
      id: 'extra_patrol', labelTh: 'สายตรวจพิเศษ', labelEn: 'Extra patrol'),
  BookingExtra(
      id: 'daily_report',
      labelTh: 'รายงานสรุปประจำวัน',
      labelEn: 'Daily summary report'),
  BookingExtra(
      id: 'liaison',
      labelTh: 'ประสานงานนิติบุคคล',
      labelEn: 'Liaison with the juristic office'),
];

/// Resolve a selection of extra-ids (subset of [catalog]) to their localized labels, preserving
/// the catalog's display order (so the folded text is stable regardless of tap order). Unknown
/// ids are dropped. Pure.
List<String> labelsForIds(
  Set<String> ids,
  List<BookingExtra> catalog,
  bool isThai,
) =>
    [
      for (final e in catalog)
        if (ids.contains(e.id)) e.label(isThai),
    ];

/// Compose the single `address` string sent to `POST /v1/bookings` from the picked location
/// address plus the form's extra detail fields. The chosen address comes first (so the guard/admin
/// still reads the site as the leading line); labelled lines for the extra-details note, the
/// selected equipment and the selected add-ons are appended only when non-empty. Bilingual labels.
/// Pure → unit-testable.
///
/// Output shape (lines omitted when their input is empty):
/// ```
/// <address>
/// รายละเอียดเพิ่มเติม: <extra details>
/// อุปกรณ์: ไฟฉาย, กุญแจมือ
/// บริการเพิ่มเติม: สายตรวจพิเศษ
/// ```
String composeAddress({
  required String address,
  required String extraDetails,
  required Set<String> equipment,
  required Set<String> addOns,
  required bool isThai,
}) {
  final lines = <String>[];
  final base = address.trim();
  if (base.isNotEmpty) lines.add(base);

  final details = extraDetails.trim();
  if (details.isNotEmpty) {
    lines.add('${isThai ? 'รายละเอียดเพิ่มเติม' : 'Details'}: $details');
  }

  final equip = labelsForIds(equipment, kSecurityEquipment, isThai);
  if (equip.isNotEmpty) {
    lines.add('${isThai ? 'อุปกรณ์' : 'Equipment'}: ${equip.join(', ')}');
  }

  final adds = labelsForIds(addOns, kAddOnServices, isThai);
  if (adds.isNotEmpty) {
    lines.add('${isThai ? 'บริการเพิ่มเติม' : 'Add-ons'}: ${adds.join(', ')}');
  }

  return lines.join('\n');
}

/// Whole hours between [start] and [end] (`end − start`, truncated toward zero), or 0 when either
/// is null or the range is non-positive. The form's time model is start/end DateTimes; the booking
/// body sends this computed integer as `hours`. Pure → unit-testable.
int hoursBetween(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 0;
  final mins = end.difference(start).inMinutes;
  if (mins <= 0) return 0;
  return mins ~/ 60;
}
