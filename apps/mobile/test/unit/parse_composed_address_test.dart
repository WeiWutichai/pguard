import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking_options.dart';
import 'package:pguard_mobile/features/booking/live_status_screen.dart';

void main() {
  group('parseComposedAddress', () {
    test('null / blank → empty (sheet shows the "Not set" fallback)', () {
      expect(parseComposedAddress(null, isThai: true), isEmpty);
      expect(parseComposedAddress('   \n  ', isThai: true), isEmpty);
    });

    test('a bare address is the single primary row', () {
      final rows = parseComposedAddress('หมู่บ้านลัดดารมย์', isThai: true);
      expect(rows, hasLength(1));
      expect(rows.first.isPrimary, isTrue);
      expect(rows.first.label, 'ที่อยู่');
      expect(rows.first.value, 'หมู่บ้านลัดดารมย์');
      expect(rows.first.icon, Icons.place_outlined);
    });

    test('splits the TH folded lines into their own labelled rows', () {
      const address = 'หมู่บ้านลัดดารมย์\n'
          'ประเภทสถานที่: หมู่บ้าน\n'
          'รายละเอียดเพิ่มเติม: ประตูหลังพัง\n'
          'อุปกรณ์: ไฟฉาย, กุญแจมือ\n'
          'บริการเพิ่มเติม: สายตรวจพิเศษ';
      final rows = parseComposedAddress(address, isThai: true);
      expect(rows, hasLength(5));

      expect(rows[0].isPrimary, isTrue);
      expect(rows[0].value, 'หมู่บ้านลัดดารมย์');

      expect(rows[1].label, 'ประเภทสถานที่');
      expect(rows[1].value, 'หมู่บ้าน');
      expect(rows[1].icon, Icons.home_outlined);

      expect(rows[2].label, 'รายละเอียดเพิ่มเติม');
      expect(rows[2].value, 'ประตูหลังพัง');
      expect(rows[2].icon, Icons.notes_outlined);

      expect(rows[3].label, 'อุปกรณ์');
      expect(rows[3].value, 'ไฟฉาย, กุญแจมือ');
      expect(rows[3].icon, Icons.security_outlined);

      expect(rows[4].label, 'บริการเพิ่มเติม');
      expect(rows[4].value, 'สายตรวจพิเศษ');
      expect(rows[4].icon, Icons.add_circle_outline);
    });

    test('matches EN label prefixes too, rendering rows in the chosen language', () {
      const address = '99 Sukhumvit Rd\n'
          'Place type: Village\n'
          'Details: back gate broken\n'
          'Equipment: Flashlight, Handcuffs\n'
          'Add-ons: Extra patrol';
      // English source labels but render the rows in Thai.
      final th = parseComposedAddress(address, isThai: true);
      expect(th, hasLength(5));
      expect(th[1].label, 'ประเภทสถานที่');
      expect(th[1].value, 'Village');
      expect(th[4].label, 'บริการเพิ่มเติม');

      // And in English.
      final en = parseComposedAddress(address, isThai: false);
      expect(en[0].label, 'Address');
      expect(en[1].label, 'Place type');
      expect(en[3].label, 'Equipment');
      expect(en[3].value, 'Flashlight, Handcuffs');
    });

    test('an unknown folded line is kept under a generic "More" row (nothing dropped)', () {
      const address = 'หมู่บ้านลัดดารมย์\n'
          'หมายเหตุพิเศษ: โทรก่อนถึง 10 นาที';
      final rows = parseComposedAddress(address, isThai: false);
      expect(rows, hasLength(2));
      expect(rows[1].label, 'More');
      // The full line is preserved verbatim.
      expect(rows[1].value, 'หมายเหตุพิเศษ: โทรก่อนถึง 10 นาที');
    });

    test('round-trips composeAddress output back into rows', () {
      final composed = composeAddress(
        address: '123 หมู่บ้านสุขใจ',
        placeTypeId: 'village',
        extraDetails: 'ประตูหลังพัง',
        equipment: const {},
        addOns: const {},
        isThai: true,
      );
      final rows = parseComposedAddress(composed, isThai: true);
      expect(rows.first.value, '123 หมู่บ้านสุขใจ');
      // Place type + details folded in → 3 rows total.
      expect(rows, hasLength(3));
      expect(rows[1].label, 'ประเภทสถานที่');
      expect(rows[2].label, 'รายละเอียดเพิ่มเติม');
      expect(rows[2].value, 'ประตูหลังพัง');
    });
  });
}
