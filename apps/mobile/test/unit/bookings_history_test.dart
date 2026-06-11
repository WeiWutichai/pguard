import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/bookings_history.dart';
import 'package:pguard_mobile/core/models/booking.dart';

Booking booking(String id, BookingStatus status) =>
    Booking(id: id, customerId: 'c1', status: status);

void main() {
  group('BookingsHistory.badge', () {
    test('completed → done, negative terminals → cancelled, rest → active',
        () {
      expect(BookingsHistory.badge(BookingStatus.completed),
          HistoryBadge.done);
      expect(BookingsHistory.badge(BookingStatus.cancelled),
          HistoryBadge.cancelled);
      expect(BookingsHistory.badge(BookingStatus.declined),
          HistoryBadge.cancelled);
      for (final s in [
        BookingStatus.requested,
        BookingStatus.accepted,
        BookingStatus.enRoute,
        BookingStatus.arrived,
        BookingStatus.pendingCompletion,
      ]) {
        expect(BookingsHistory.badge(s), HistoryBadge.active,
            reason: '$s should badge as active');
      }
    });
  });

  group('BookingsHistory.filter', () {
    final all = [
      booking('b1', BookingStatus.completed),
      booking('b2', BookingStatus.cancelled),
      booking('b3', BookingStatus.declined),
      booking('b4', BookingStatus.enRoute),
      booking('b5', BookingStatus.requested),
    ];

    List<String> ids(BookingsHistoryFilter f) =>
        BookingsHistory.filter(all, f).map((b) => b.id).toList();

    test('all keeps everything, order preserved', () {
      expect(ids(BookingsHistoryFilter.all), ['b1', 'b2', 'b3', 'b4', 'b5']);
    });

    test('done keeps only completed', () {
      expect(ids(BookingsHistoryFilter.done), ['b1']);
    });

    test('cancelled keeps cancelled AND declined', () {
      expect(ids(BookingsHistoryFilter.cancelled), ['b2', 'b3']);
    });

    test('active keeps every non-terminal (incl. requested)', () {
      expect(ids(BookingsHistoryFilter.active), ['b4', 'b5']);
    });
  });

  test('filter chip labels are the exact design strings', () {
    expect(
      BookingsHistoryFilter.values.map((f) => f.label),
      ['ทั้งหมด / All', 'สำเร็จ / Done', 'ยกเลิก / Cancelled', 'กำลังทำ'],
    );
  });

  test('badge words are the literal design badge strings', () {
    expect(HistoryBadge.values.map((b) => b.label),
        ['active', 'done', 'cancelled']);
  });
}
