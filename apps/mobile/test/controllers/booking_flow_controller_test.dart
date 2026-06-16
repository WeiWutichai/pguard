import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/booking_flow_controller.dart';
import 'package:pguard_mobile/core/models/geo.dart';
import 'package:pguard_mobile/core/models/payment.dart';
import 'package:pguard_mobile/core/models/service_catalog.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';

import '../support/fakes.dart';

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
        'tip': '0',
        'lat': req['lat'],
        'lng': req['lng'],
        'created_at': '2026-06-05T10:00:00Z',
        'updated_at': '2026-06-05T10:00:00Z',
      };

  test(
      'happy path: select service → create booking → discover guards → select → pay',
      () async {
    final api = FakeApi(
      onGet: (path, _) async {
        expect(path, '/available-guards');
        return [
          {
            'guard_id': 'guard-aaaa-1111',
            'years_of_experience': 6,
            'average_rating': '4.90',
            'review_count': 188,
          },
          {
            'guard_id': 'guard-bbbb-2222',
            'years_of_experience': null,
            'average_rating': null,
            'review_count': 0,
          },
        ];
      },
      onPost: (path, data) async {
        final body = data as Map<String, dynamic>;
        switch (path) {
          case '/bookings':
            expect(body['address'], '123 ลัดดารมย์ ซ.5');
            expect(body['hours'], 8);
            expect(body['guard_count'], 2);
            expect(body['scheduled_at'], isA<String>());
            return bookingJson(body);
          case '/payments':
            expect(body['booking_id'], 'bk1');
            // ฿500 × 8 × 2 = ฿8,000 + ฿50 tip = ฿8,050.00
            expect(body['amount'], '8050.00');
            expect(body['payment_method'], 'promptpay');
            return {
              'id': 'pay1',
              'booking_id': 'bk1',
              'customer_id': 'c1',
              'guard_id': null,
              'amount': body['amount'],
              'expected_total': '8000.00',
              'payment_method': 'promptpay',
              'status': 'completed',
              'created_at': '2026-06-05T10:01:00Z',
              'updated_at': '2026-06-05T10:01:00Z',
            };
          default:
            throw StateError('unexpected POST $path');
        }
      },
    );
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    BookingFlowState state() => c.read(bookingFlowControllerProvider);

    // Form input
    ctrl.selectService(SecurityService.condo);
    ctrl.setAddress('123 ลัดดารมย์ ซ.5');
    ctrl.setSchedule(DateTime.utc(2026, 6, 6, 14));
    ctrl.setHours(8);
    ctrl.setGuardCount(2);
    expect(state().service, SecurityService.condo);

    // Create booking → authoritative base_fee captured
    expect(await ctrl.createBooking(), isTrue);
    expect(state().booking?.id, 'bk1');
    expect(state().booking?.baseFee, '500.00');
    expect(state().bookingSubtotalSatang, 800000); // ฿8,000

    // Discover guards (single GET, no polling)
    expect(await ctrl.loadGuards(), isTrue);
    expect(state().guards.length, 2);
    expect(state().guards.first.reviewCount, 188);
    expect(state().guards.first.rating, 4.9);

    // Select a guard (preview only — no network call)
    ctrl.selectGuard(state().guards.first.guardId);
    expect(state().selectedGuardId, 'guard-aaaa-1111');

    // Tip + pay → derived amount sent, server total verified
    ctrl.setTipSatang(5000); // ฿50
    expect(state().payTotalSatang, 805000);
    expect(await ctrl.pay(PaymentMethod.promptpay), isTrue);
    expect(state().payment?.isCompleted, isTrue);

    // Exactly one REST call per step, in order — proves there is NO polling.
    expect(api.calls, ['POST /bookings', 'GET /available-guards', 'POST /payments']);
    expect(api.getCount, 1);
  });

  test('createBooking rejects an empty address before any network call', () async {
    final api = FakeApi(
      onPost: (_, __) async => throw StateError('should not be called'),
    );
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    ctrl.selectService(SecurityService.village);
    ctrl.setAddress('   ');
    expect(await ctrl.createBooking(), isFalse);
    expect(c.read(bookingFlowControllerProvider).error, contains('สถานที่'));
    expect(api.calls, isEmpty);
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
    expect(await ctrl.createBooking(), isTrue);

    expect(sent!['lat'], 13.7401);
    expect(sent!['lng'], 100.5331);
    expect(sent!['address'], 'หมู่บ้านลัดดารมย์');
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
    expect(await ctrl.createBooking(), isTrue);

    expect(sent!.containsKey('lat'), isFalse);
    expect(sent!.containsKey('lng'), isFalse);
    expect(c.read(bookingFlowControllerProvider).booking?.lat, isNull);
  });

  test('pay surfaces the server message and keeps no payment', () async {
    final api = FakeApi(
      onPost: (path, data) async {
        if (path == '/bookings') return bookingJson(data as Map<String, dynamic>);
        if (path == '/payments') {
          throw const ApiException(
              message: 'Payment failed', code: 'BAD_REQUEST', statusCode: 400);
        }
        throw StateError('unexpected POST $path');
      },
    );
    final c = container(api: api);
    final ctrl = c.read(bookingFlowControllerProvider.notifier);
    ctrl.setAddress('123');
    ctrl.setHours(8);
    ctrl.setGuardCount(1);
    expect(await ctrl.createBooking(), isTrue);
    expect(await ctrl.pay(PaymentMethod.creditCard), isFalse);
    expect(c.read(bookingFlowControllerProvider).error, 'Payment failed');
    expect(c.read(bookingFlowControllerProvider).payment, isNull);
  });
}
