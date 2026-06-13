// Pure filter/badge logic for the customer "การจอง" history tab — no Flutter imports,
// 100% unit-testable. UI per More_Screens.md Screen 5 "Hirer History".

import '../models/booking.dart';

/// The history filter tabs (design: ทั้งหมด / สำเร็จ / ยกเลิก / กำลังทำ).
enum BookingsHistoryFilter {
  all('ทั้งหมด', 'All'),
  done('สำเร็จ', 'Done'),
  cancelled('ยกเลิก', 'Cancelled'),
  // The design shows this tab Thai-only (EN hidden) — same word in both locales.
  active('กำลังทำ', 'In progress');

  const BookingsHistoryFilter(this._th, this._en);

  final String _th;
  final String _en;

  /// Single-language chip label driven by the active locale, exact design strings.
  String label(bool isThai) => isThai ? _th : _en;
}

/// The row badge kind (the design badges are the literal lowercase words).
enum HistoryBadge {
  active('active'),
  done('done'),
  cancelled('cancelled');

  const HistoryBadge(this.label);

  final String label;
}

/// Pure classification + filtering for the history list.
class BookingsHistory {
  const BookingsHistory._();

  /// Which badge a booking row carries: negative terminals → cancelled (red), completed →
  /// done (green), everything still in flight (incl. `requested`) → active (amber).
  static HistoryBadge badge(BookingStatus status) {
    if (BookingLifecycle.isNegativeTerminal(status)) {
      return HistoryBadge.cancelled;
    }
    if (status == BookingStatus.completed) return HistoryBadge.done;
    return HistoryBadge.active;
  }

  /// Whether [status] belongs under [filter].
  static bool matches(BookingStatus status, BookingsHistoryFilter filter) {
    switch (filter) {
      case BookingsHistoryFilter.all:
        return true;
      case BookingsHistoryFilter.done:
        return status == BookingStatus.completed;
      case BookingsHistoryFilter.cancelled:
        return BookingLifecycle.isNegativeTerminal(status);
      case BookingsHistoryFilter.active:
        return !BookingLifecycle.isTerminal(status);
    }
  }

  /// [all] (server-ordered newest first) narrowed to [filter], order preserved.
  static List<Booking> filter(
          List<Booking> all, BookingsHistoryFilter filter) =>
      all.where((b) => matches(b.status, filter)).toList();
}
