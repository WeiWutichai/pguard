import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/booking.dart';
import 'package:pguard_mobile/features/guard/widgets/online_card.dart';

/// `OnlineCard.hasActiveJob` (#123) — whether the guard currently has a job in hand
/// (accepted / en_route / arrived / pending_completion), which drives the distinct "busy" toggle
/// state. Best-effort over the cached jobs feed: a null feed (loading / failed) reports `false`.
Booking job(BookingStatus status) =>
    Booking(id: 'b', customerId: 'c', status: status, guardId: 'g');

void main() {
  group('OnlineCard.hasActiveJob', () {
    test('true for each in-hand active status', () {
      for (final s in [
        BookingStatus.accepted,
        BookingStatus.enRoute,
        BookingStatus.arrived,
        BookingStatus.pendingCompletion,
      ]) {
        expect(OnlineCard.hasActiveJob([job(s)]), isTrue, reason: s.wire);
      }
    });

    test('false when only terminal / requested jobs are present', () {
      expect(
        OnlineCard.hasActiveJob([
          job(BookingStatus.completed),
          job(BookingStatus.cancelled),
          job(BookingStatus.declined),
          job(BookingStatus.requested),
        ]),
        isFalse,
      );
    });

    test('false for a null (loading / failed) feed and an empty list', () {
      expect(OnlineCard.hasActiveJob(null), isFalse);
      expect(OnlineCard.hasActiveJob(const []), isFalse);
    });

    test('true if ANY job in the feed is active (mixed list)', () {
      expect(
        OnlineCard.hasActiveJob([
          job(BookingStatus.completed),
          job(BookingStatus.arrived),
        ]),
        isTrue,
      );
    });
  });
}
