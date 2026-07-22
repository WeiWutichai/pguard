import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/booking.dart';
import '../models/progress_report.dart';
import '../providers.dart';
import 'booking_status_controller.dart';

part 'progress_reports_controller.g.dart';

/// The customer-visible hourly check-in state for one booking — drives the live-status
/// screen's "รายงานรายชั่วโมง" timeline and the remaining-time block. Pure derivations
/// (no Flutter, no I/O) so the timeline/clock logic unit-tests without a container.
class HourlyProgress {
  const HourlyProgress({required this.booking, required this.reports});

  final Booking booking;

  /// The booking's check-in reports, `hour_number` order (server-sorted).
  final List<ProgressReport> reports;

  int get bookedHours => booking.hours ?? 0;

  /// The report covering [hour] (1-based), or `null` if not yet checked in.
  ProgressReport? reportFor(int hour) {
    for (final r in reports) {
      if (r.hourNumber == hour) return r;
    }
    return null;
  }

  /// How many of the booked hours have a report (the "2/5" numerator).
  int get reportedCount {
    var n = 0;
    for (var h = 1; h <= bookedHours; h++) {
      if (reportFor(h) != null) n++;
    }
    return n;
  }

  /// The first hour without a report — the timeline's "current" node. `null` once all
  /// booked hours are reported.
  int? get currentHour {
    for (var h = 1; h <= bookedHours; h++) {
      if (reportFor(h) == null) return h;
    }
    return null;
  }

  /// The work-start basis DERIVED from the reports: the Booking API does not expose
  /// `work_started_at` (it is the server-internal proration basis), but hour N's check-in
  /// opens N−1 hours after start — so each report anchors the start, and the earliest
  /// anchor is the best display estimate. `null` until the first check-in lands.
  DateTime? get workStartedAt {
    DateTime? best;
    for (final r in reports) {
      final anchored = r.createdAt.subtract(Duration(hours: r.hourNumber - 1));
      if (best == null || anchored.isBefore(best)) best = anchored;
    }
    return best;
  }
}

/// Customer-side hourly-report controller. Phase 2 rules: it WATCHES the booking-status
/// controller, so every status frame pushed over the booking WebSocket re-runs [build],
/// which re-pulls ONE `GET /v1/bookings/{id}/progress-reports` snapshot (the contract's
/// `listProgressReports` is participants-only — the booking's customer may read). There is
/// no timer in this path.
@riverpod
class ProgressReportsController extends _$ProgressReportsController {
  @override
  Future<HourlyProgress> build(String bookingId) async {
    // Rebuilds on every pushed status event (the WS is owned by BookingStatusController).
    final booking =
        await ref.watch(bookingStatusControllerProvider(bookingId).future);

    // limit=200 (> MAX_BOOKING_HOURS=168) so a long booking's check-ins beyond the server default
    // page size (50) don't vanish from the timeline — mirrors ActiveJobController.build (deep-review).
    final data = await ref.read(pguardApiProvider).get(
        '/bookings/$bookingId/progress-reports',
        query: const {'limit': 200});
    final reports = (data as List)
        .whereType<Map<String, dynamic>>()
        .map(ProgressReport.fromJson)
        .toList();
    return HourlyProgress(booking: booking, reports: reports);
  }
}
