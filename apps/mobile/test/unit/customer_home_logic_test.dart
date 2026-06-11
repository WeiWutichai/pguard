import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/customer_home_controller.dart';
import 'package:pguard_mobile/core/controllers/progress_reports_controller.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/core/models/progress_report.dart';

Booking booking(String id, BookingStatus status, {String? address}) => Booking(
      id: id,
      customerId: 'c1',
      status: status,
      address: address,
      hours: 5,
      guardCount: 1,
      baseFee: '230.00',
      tip: '0',
    );

ProgressReport report(int hour, DateTime createdAt) => ProgressReport(
      id: 'r$hour',
      bookingId: 'b1',
      guardId: 'g1',
      hourNumber: hour,
      photoKey: 'k',
      photoUrl: 'u',
      createdAt: createdAt,
    );

void main() {
  group('CustomerHomeController section pickers (list is newest-first)', () {
    final all = [
      booking('b3', BookingStatus.arrived, address: 'คอนโด ไอดีโอ'),
      booking('b2', BookingStatus.completed, address: 'หมู่บ้านลัดดารมย์ ซ.5'),
      booking('b1', BookingStatus.cancelled),
    ];

    test('ongoing = newest non-terminal', () {
      expect(CustomerHomeController.ongoing(all)?.id, 'b3');
      expect(CustomerHomeController.ongoing(const []), isNull);
    });

    test('latest = newest terminal', () {
      expect(CustomerHomeController.latest(all)?.id, 'b2');
      expect(
          CustomerHomeController.latest(
              [booking('x', BookingStatus.requested)]),
          isNull);
    });

    test('recentAddress = first booking with a non-empty address', () {
      expect(CustomerHomeController.recentAddress(all), 'คอนโด ไอดีโอ');
      expect(
          CustomerHomeController.recentAddress(
              [booking('x', BookingStatus.requested)]),
          isNull);
    });

    test('bookingTotalSatang = base_fee × hours × guards + tip', () {
      expect(bookingTotalSatang(all.first), 23000 * 5);
    });

    test('thaiShortDate renders the Thai month abbreviation', () {
      expect(thaiShortDate(DateTime(2026, 6, 2)), '2 มิ.ย.');
    });
  });

  group('HourlyProgress derivations', () {
    final start = DateTime.utc(2026, 6, 10, 7); // 14:00 ICT
    final progress = HourlyProgress(
      booking: booking('b1', BookingStatus.arrived),
      reports: [
        report(1, start),
        report(2, start.add(const Duration(hours: 1, minutes: 3))),
      ],
    );

    test('reportedCount / currentHour follow the booked hours', () {
      expect(progress.bookedHours, 5);
      expect(progress.reportedCount, 2);
      expect(progress.currentHour, 3);
      expect(progress.reportFor(1), isNotNull);
      expect(progress.reportFor(3), isNull);
    });

    test('workStartedAt anchors from the earliest report', () {
      // Hour 2's check-in anchors to createdAt − 1h; hour 1's own stamp is earlier.
      expect(progress.workStartedAt, start);
    });

    test('workStartedAt is null with no reports', () {
      final empty = HourlyProgress(
          booking: booking('b1', BookingStatus.arrived), reports: const []);
      expect(empty.workStartedAt, isNull);
      expect(empty.currentHour, 1);
    });
  });
}
