import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/booking_flow_controller.dart';
import 'package:pguard_mobile/core/models/booking_options.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/core/models/service_catalog.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

/// A catalog service stand-in (mirrors one `GET /v1/services` row parsed to satang).
const _condo = ServiceOption(
  id: 'svc-condo-0001',
  nameTh: 'คอนโด',
  nameEn: 'Condo',
  baseFeeSatang: 25000, // ฿250.00/hr
  minHours: 4,
);

void main() {
  ProviderContainer container({required FakeApi api}) {
    final c = ProviderContainer(overrides: [
      pguardApiProvider.overrideWithValue(api),
      appStoreProvider.overrideWithValue(InMemoryStore()..access = 'token'),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Map<String, dynamic> bookingJson(Map<String, dynamic> req) => {
        'id': 'bk1',
        'customer_id': 'c1',
        'guard_id': null,
        'status': 'requested',
        'address': req['address'],
        'scheduled_at': req['scheduled_at'],
        'hours': req['hours'],
        'base_fee': '500.00',
        'guard_count': req['guard_count'],
        'tip': req['tip'] ?? '0',
        'lat': req['lat'],
        'lng': req['lng'],
        'created_at': '2026-06-05T10:00:00Z',
        'updated_at': '2026-06-05T10:00:00Z',
      };

  test(
      'happy path (POST-PAY): form (start/end + tip) → create booking → discover guards → select; NO charge',
      () async {
    Map<String, dynamic>? bookingBody;
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/available-guards');
        return [
          {
            'guard_id': 'guard-aaaa-1111',
            // Enriched contract: real name + avatar URL (once the backend FLAG ships).
            'display_name': 'สมชาย มั่นคง',
            'avatar_url': 'https://cdn.example/guard-aaaa.jpg',
            'years_of_experience': 6,
            'average_rating': '4.90',
            'review_count': 188,
          },
          {
            'guard_id': 'guard-bbbb-2222',
            // Un-enriched row (no name/avatar) — must still parse and fall back.
            'years_of_experience': null,
            'average_rating': null,
            'review_count': 0,
          },
        ];
      },
      onPost: (path, data) async {
        final body = data as Map<String, dynamic>;
        expect(path, '/bookings'); // post-pay: there is NO /payments call
        // The chosen location address is the leading line of the composed address.
        expect((body['address'] as String).startsWith('123 ลัดดารมย์ ซ.5'),
            isTrue);
        expect(body['hours'], 8); // computed (end − start)
        expect(body['guard_count'], 2);
        expect(body['scheduled_at'], isA<String>());
        // The chosen catalog service is sent by ID only — the client NEVER sends a price.
        expect(body['service_id'], 'svc-condo-0001');
        expect(body.containsKey('base_fee'), isFalse);
        // The flat tip rides the booking (sent as a decimal string), not a separate charge.
        expect(body['tip'], '50.00');
        bookingBody = body;
        return bookingJson(body);
      },
    );
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    BookingFlowState state() => c.read(bookingFlowControllerProvider);

    // Form input — start + end define the duration; the tip rides the booking under post-pay.
    ctrl.selectService(_condo);
    ctrl.setAddress('123 ลัดดารมย์ ซ.5');
    ctrl.setStart(DateTime.utc(2026, 6, 6, 14));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 22)); // 8h
    ctrl.setGuardCount(2);
    ctrl.setTipSatang(5000); // ฿50
    expect(state().service, _condo);
    expect(state().hours, 8); // computed
    expect(state().scheduledAt, DateTime.utc(2026, 6, 6, 14)); // = start
    // The indicative est is service-derived (baseFeeSatang); est-with-tip is display-only.
    expect(state().estimateHourlySatang, 25000);
    expect(state().estimateWithTipSatang, state().estimateTotalSatang + 5000);

    // Create booking → authoritative base_fee captured; tip + service_id sent in the body.
    expect(await ctrl.createBooking(), isTrue);
    expect(state().booking?.id, 'bk1');
    expect(state().booking?.baseFee, '500.00');
    expect(bookingBody?['tip'], '50.00');
    expect(bookingBody?['service_id'], 'svc-condo-0001');

    // Discover guards (single GET, no polling)
    expect(await ctrl.loadGuards(), isTrue);
    expect(state().guards.length, 2);
    expect(state().guards.first.reviewCount, 188);
    expect(state().guards.first.rating, 4.9);
    // Enriched fields parse: real name + photo on the first guard…
    expect(state().guards.first.displayName, 'สมชาย มั่นคง');
    expect(state().guards.first.avatarUrl, 'https://cdn.example/guard-aaaa.jpg');
    expect(state().guards.first.hasPhoto, isTrue);
    expect(state().guards.first.displayLabel(true), 'สมชาย มั่นคง');
    // …and the un-enriched guard falls back to the id handle + initials avatar.
    expect(state().guards[1].displayName, isNull);
    expect(state().guards[1].hasPhoto, isFalse);
    expect(state().guards[1].displayLabel(true), startsWith('เจ้าหน้าที่ #'));

    // Select a guard (preview only — no network call)
    ctrl.selectGuard(state().guards.first.guardId);
    expect(state().selectedGuardId, 'guard-aaaa-1111');

    // Exactly one REST call per step, in order — proves NO polling and NO up-front charge.
    expect(api.calls, ['POST /bookings', 'GET /available-guards']);
    expect(api.getCount, 1);
  });

  test('hours are computed from start/end (whole hours, truncated)', () {
    // pure helper coverage
    expect(hoursBetween(null, null), 0);
    expect(
        hoursBetween(DateTime.utc(2026, 1, 1, 9), DateTime.utc(2026, 1, 1, 8)),
        0); // non-positive
    expect(
        hoursBetween(
            DateTime.utc(2026, 1, 1, 9), DateTime.utc(2026, 1, 1, 17, 30)),
        8); // 8h30m → 8

    final c = container(api: FakeApi());
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    BookingFlowState state() => c.read(bookingFlowControllerProvider);
    ctrl.setStart(DateTime.utc(2026, 6, 6, 14));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 23, 45)); // 9h45m
    expect(state().hours, 9);
    expect(state().scheduledAt, DateTime.utc(2026, 6, 6, 14)); // = start
  });

  test('a duration preset sets end = start + preset hours', () {
    final c = container(api: FakeApi());
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    BookingFlowState state() => c.read(bookingFlowControllerProvider);
    ctrl.setStart(DateTime.utc(2026, 6, 6, 9));
    ctrl.setDurationPreset(12);
    expect(state().hours, 12);
    expect(state().endAt, DateTime.utc(2026, 6, 6, 21));
    // A preset with no start chosen still yields a complete 8h range (anchored to a default start).
    final c2 = container(api: FakeApi());
    final ctrl2 = c2.read(bookingFlowControllerProvider.notifier);
    ctrl2.setDurationPreset(8);
    expect(c2.read(bookingFlowControllerProvider).startAt, isNotNull);
    expect(c2.read(bookingFlowControllerProvider).hours, 8);
  });

  test('min_hours is enforced: below-min flags meetsMinHours and blocks create', () async {
    Map<String, dynamic>? sent;
    final api = FakeApi(onPost: (_, data) async {
      sent = data as Map<String, dynamic>;
      return bookingJson(sent!);
    });
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    BookingFlowState state() => c.read(bookingFlowControllerProvider);

    ctrl.selectService(_condo); // min 4h
    ctrl.setAddress('123');
    ctrl.setStart(DateTime.utc(2026, 6, 6, 14));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 16)); // only 2h → below min
    expect(state().hours, 2);
    expect(state().meetsMinHours, isFalse);

    // Create is blocked client-side (no network call) with a min-hours error.
    expect(await ctrl.createBooking(), isFalse);
    expect(state().error, contains('4'));
    expect(api.calls, isEmpty);

    // Bumping the end to meet the floor clears the warning and lets create through.
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 18)); // 4h
    expect(state().meetsMinHours, isTrue);
    expect(await ctrl.createBooking(), isTrue);
    expect(sent!['hours'], 4);
  });

  test('selectService extends the end up to the service min_hours when too short', () {
    final c = container(api: FakeApi());
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    BookingFlowState state() => c.read(bookingFlowControllerProvider);
    // A short 1h range, then selecting a min-4 service stretches the end to start + 4h.
    ctrl.setStart(DateTime.utc(2026, 6, 6, 9));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 10)); // 1h
    ctrl.selectService(_condo);
    expect(state().hours, 4);
    expect(state().endAt, DateTime.utc(2026, 6, 6, 13));
  });

  test('setStart re-anchors a now-invalid end to start + minHours', () {
    final c = container(api: FakeApi());
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    BookingFlowState state() => c.read(bookingFlowControllerProvider);
    ctrl.selectService(_condo); // min 4
    ctrl.setStart(DateTime.utc(2026, 6, 6, 9));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 15)); // 6h, valid
    // Moving the start past the end re-anchors the end to start + minHours (no negative range).
    ctrl.setStart(DateTime.utc(2026, 6, 6, 20));
    expect(state().endAt, DateTime.utc(2026, 6, 7, 0)); // 20:00 + 4h
    expect(state().hours, 4);
  });

  test('the composed address folds in the extra details, equipment and add-ons', () async {
    Map<String, dynamic>? sent;
    final api = FakeApi(onPost: (_, data) async {
      sent = data as Map<String, dynamic>;
      return bookingJson(sent!);
    });
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);

    ctrl.setAddress('123 หมู่บ้านลัดดารมย์');
    ctrl.setStart(DateTime.utc(2026, 6, 6, 14));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 22));
    ctrl.setExtraDetails('โทรหาเมื่อถึงประตูหน้า');
    ctrl.toggleEquipment('flashlight');
    ctrl.toggleEquipment('handcuffs');
    ctrl.toggleAddOn('extra_patrol');

    expect(await ctrl.createBooking(), isTrue);
    final addr = sent!['address'] as String;
    // Address is the leading line.
    expect(addr.startsWith('123 หมู่บ้านลัดดารมย์'), isTrue);
    // The note + selected equipment + selected add-ons are appended as labelled lines.
    expect(addr, contains('โทรหาเมื่อถึงประตูหน้า'));
    expect(addr, contains('ไฟฉาย'));
    expect(addr, contains('กุญแจมือ'));
    expect(addr, contains('สายตรวจพิเศษ'));
    // Unselected items are NOT folded in.
    expect(addr.contains('เสื้อเกราะ'), isFalse);
    expect(addr.contains('รายงานสรุปประจำวัน'), isFalse);
  });

  test('toggleEquipment/toggleAddOn add then remove an id', () {
    final c = container(api: FakeApi());
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    BookingFlowState state() => c.read(bookingFlowControllerProvider);
    ctrl.toggleEquipment('uniform');
    expect(state().equipment, {'uniform'});
    ctrl.toggleEquipment('uniform'); // off again
    expect(state().equipment, isEmpty);
    ctrl.toggleAddOn('liaison');
    expect(state().addOns, {'liaison'});
  });

  test('composeAddress (pure) omits empty lines and is order-stable', () {
    // No extras → just the trimmed address, no trailing lines.
    expect(
      composeAddress(
        address: '  123 ถนนสุขุมวิท  ',
        extraDetails: '',
        equipment: const {},
        addOns: const {},
        isThai: true,
      ),
      '123 ถนนสุขุมวิท',
    );
    // Equipment order follows the catalog, not the selection (tap) order.
    final out = composeAddress(
      address: 'site',
      extraDetails: '',
      equipment: {'handcuffs', 'flashlight'}, // reversed vs catalog
      addOns: const {},
      isThai: true,
    );
    expect(out.indexOf('ไฟฉาย') < out.indexOf('กุญแจมือ'), isTrue);
    // Place type folds in as a labelled line, after the address and before the equipment.
    final pt = composeAddress(
      address: 'site',
      placeTypeId: 'village',
      extraDetails: '',
      equipment: {'flashlight'},
      addOns: const {},
      isThai: true,
    );
    expect(pt.contains('ประเภทสถานที่: หมู่บ้าน'), isTrue);
    expect(pt.indexOf('ประเภทสถานที่') < pt.indexOf('อุปกรณ์'), isTrue);
    // An unknown place-type id is dropped (no line), never throws.
    expect(
      composeAddress(
        address: 'site',
        placeTypeId: 'bogus',
        extraDetails: '',
        equipment: const {},
        addOns: const {},
        isThai: true,
      ),
      'site',
    );
  });

  test('setPlaceType selects the place type and folds it into the sent address', () {
    final c = container(api: FakeApi());
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    ctrl.setAddress('โรงงาน ABC');
    ctrl.setPlaceType('factory');
    final s = c.read(bookingFlowControllerProvider);
    expect(s.placeTypeId, 'factory');
    expect(s.composedAddressFor(true).contains('ประเภทสถานที่: โรงงาน'), isTrue);
  });

  test('price = base × hours × guards + tip (display estimate, exact satang)', () {
    final c = container(api: FakeApi());
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    ctrl.selectService(_condo); // ฿250/hr
    ctrl.setStart(DateTime.utc(2026, 6, 6, 14));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 22)); // 8h
    ctrl.setGuardCount(3);
    ctrl.setTipSatang(5000); // ฿50
    final s = c.read(bookingFlowControllerProvider);
    expect(s.estimateHourlySatang, 25000);
    expect(s.estimateTotalSatang, 25000 * 8 * 3); // 6,000.00
    expect(s.estimateWithTipSatang, 25000 * 8 * 3 + 5000); // + ฿50
  });

  test('createBooking rejects an empty address before any network call', () async {
    final api = FakeApi(
      onPost: (_, __) async => throw StateError('should not be called'),
    );
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    ctrl.selectService(_condo);
    ctrl.setStart(DateTime.utc(2026, 6, 6, 14));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 22));
    ctrl.setAddress('   ');
    expect(await ctrl.createBooking(), isFalse);
    expect(c.read(bookingFlowControllerProvider).error, contains('สถานที่'));
    expect(api.calls, isEmpty);
  });

  test('omits service_id when no service is selected (default min 1h)', () async {
    Map<String, dynamic>? sent;
    final api = FakeApi(onPost: (_, data) async {
      sent = data as Map<String, dynamic>;
      return bookingJson(sent!);
    });
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    BookingFlowState state() => c.read(bookingFlowControllerProvider);

    // No service selected → default min is 1 hour and create sends no service_id.
    ctrl.setAddress('123');
    ctrl.setStart(DateTime.utc(2026, 6, 6, 14));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 16)); // 2h ≥ default min 1
    expect(state().minHours, 1);
    expect(await ctrl.createBooking(), isTrue);
    expect(sent!.containsKey('service_id'), isFalse);
    expect(sent!['hours'], 2);
  });

  test(
      'createBooking sends the map-pinned lat/lng and parses them back onto the booking',
      () async {
    Map<String, dynamic>? sent;
    final api = FakeApi(onPost: (path, data) async {
      expect(path, '/bookings');
      sent = data as Map<String, dynamic>;
      return bookingJson(sent!);
    });
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);

    // Picking on the map captures the coordinate AND fills the sent address.
    ctrl.setLocation(const GeoPlace(
        point: GeoPoint(13.7401, 100.5331), placeName: 'หมู่บ้านลัดดารมย์'));
    ctrl.setStart(DateTime.utc(2026, 6, 6, 14));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 22));
    expect(await ctrl.createBooking(), isTrue);

    expect(sent!['lat'], 13.7401);
    expect(sent!['lng'], 100.5331);
    expect((sent!['address'] as String).startsWith('หมู่บ้านลัดดารมย์'), isTrue);
    // Round-trips onto the created booking (so the guard can read the site location).
    final booking = c.read(bookingFlowControllerProvider).booking;
    expect(booking?.lat, 13.7401);
    expect(booking?.lng, 100.5331);
  });

  test('createBooking omits lat/lng when only a typed address is used (no map pick)',
      () async {
    Map<String, dynamic>? sent;
    final api = FakeApi(onPost: (_, data) async {
      sent = data as Map<String, dynamic>;
      return bookingJson(sent!);
    });
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    ctrl.setAddress('123 ลัดดารมย์ ซ.5');
    ctrl.setStart(DateTime.utc(2026, 6, 6, 14));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 22));
    expect(await ctrl.createBooking(), isTrue);

    expect(sent!.containsKey('lat'), isFalse);
    expect(sent!.containsKey('lng'), isFalse);
    expect(c.read(bookingFlowControllerProvider).booking?.lat, isNull);
  });

  test('createBooking surfaces the server message and keeps no booking', () async {
    final api = FakeApi(
      onPost: (path, _) async {
        expect(path, '/bookings');
        throw const ApiException(
            message: 'Booking failed', code: 'BAD_REQUEST', statusCode: 400);
      },
    );
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    ctrl.setAddress('123');
    ctrl.setStart(DateTime.utc(2026, 6, 6, 14));
    ctrl.setEnd(DateTime.utc(2026, 6, 6, 22));
    ctrl.setGuardCount(1);
    expect(await ctrl.createBooking(), isFalse);
    expect(c.read(bookingFlowControllerProvider).error, 'Booking failed');
    expect(c.read(bookingFlowControllerProvider).booking, isNull);
  });
}
