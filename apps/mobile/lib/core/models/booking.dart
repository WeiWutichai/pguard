// Booking domain model + the lifecycle state machine the live-status UI renders.
//
// Mirrors the backend `booking.booking_status` enum (contracts/openapi/booking.yaml). The
// lifecycle helpers (BookingLifecycle) are PURE (no Flutter imports) so the stepper logic
// is unit-testable; colors live in the widget layer.

import 'money.dart';

/// The booking lifecycle status (snake_case wire values match the backend enum).
enum BookingStatus {
  requested('requested'),
  accepted('accepted'),
  declined('declined'),
  enRoute('en_route'),
  arrived('arrived'),
  pendingCompletion('pending_completion'),
  completed('completed'),
  cancelled('cancelled');

  const BookingStatus(this.wire);

  /// The snake_case value as it appears on the wire.
  final String wire;

  /// Parse a wire value; `null` if unknown (forward-compatible — UI ignores unknowns).
  static BookingStatus? tryParse(String? value) {
    if (value == null) return null;
    for (final s in BookingStatus.values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// The gateway's sentinel "status" for a guard CHECK-IN (`booking.progress_reported`). It is NOT
/// a lifecycle status — the booking stays `arrived`. It rides the same `booking_status` frame as a
/// lightweight live NUDGE so the customer's live screen re-pulls its hourly-report timeline + the
/// work countdown the instant the guard submits a photo, with no manual refresh. Mirrors the
/// gateway's `PROGRESS_REPORTED_NUDGE` (`services/api-gateway/src/domain/ws.rs`).
const String _progressReportedNudge = 'progress_reported';

/// One real-time event pushed over the booking-status WebSocket.
/// Envelope (documented contract — see booking_status_socket.dart):
/// `{ "type":"booking_status", "booking_id", "status", "occurred_at", "guard_id"? }`.
///
/// Two shapes ride this frame:
///  - a LIFECYCLE transition ([status] non-null) — folded into the booking by [Booking.applyEvent];
///  - a REFRESH-ONLY nudge ([status] null, [isRefresh] true) — a guard check-in. It carries NO
///    status change; it only signals dependents (the progress-reports controller) to re-pull.
class BookingStatusEvent {
  const BookingStatusEvent({
    required this.bookingId,
    required this.status,
    required this.occurredAt,
    this.guardId,
    this.isRefresh = false,
  });

  final String bookingId;

  /// The lifecycle status this frame advances to, or `null` for a refresh-only nudge (a check-in).
  final BookingStatus? status;
  final DateTime occurredAt;
  final String? guardId;

  /// Whether this frame is a refresh-only nudge (a guard check-in): no status change, just a
  /// signal for the live screen to re-pull its progress-reports + countdown.
  final bool isRefresh;

  /// Parse a decoded WS frame; returns `null` if it is not a well-formed `booking_status`
  /// message (so the socket can ignore heartbeats / unknown frames).
  static BookingStatusEvent? tryParse(Map<String, dynamic> json) {
    if (json['type'] != 'booking_status') return null;
    final bookingId = json['booking_id'] as String?;
    if (bookingId == null) return null;
    final rawStatus = json['status'] as String?;
    final occurredRaw = json['occurred_at'] as String?;
    final occurredAt =
        (occurredRaw != null ? DateTime.tryParse(occurredRaw) : null)
                ?.toUtc() ??
            DateTime.now().toUtc();
    // A guard CHECK-IN nudge: not a lifecycle status, so [status] stays null and [isRefresh] is set.
    if (rawStatus == _progressReportedNudge) {
      return BookingStatusEvent(
        bookingId: bookingId,
        status: null,
        occurredAt: occurredAt,
        guardId: json['guard_id'] as String?,
        isRefresh: true,
      );
    }
    final status = BookingStatus.tryParse(rawStatus);
    if (status == null)
      return null; // unknown status (and not a nudge) — ignore forward-compat
    return BookingStatusEvent(
      bookingId: bookingId,
      status: status,
      occurredAt: occurredAt,
      guardId: json['guard_id'] as String?,
    );
  }
}

/// A booking as returned by `GET /v1/bookings/{id}` (money fields are decimal STRINGS).
class Booking {
  const Booking({
    required this.id,
    required this.customerId,
    required this.status,
    this.guardId,
    this.address,
    this.scheduledAt,
    this.hours,
    this.guardCount,
    this.baseFee,
    this.tip,
    this.lat,
    this.lng,
    this.paidAt,
    this.workStartedAt,
  });

  final String id;
  final String customerId;
  final String? guardId;
  final BookingStatus status;
  final String? address;
  final DateTime? scheduledAt;
  final int? hours;
  final int? guardCount;

  /// Server-owned ฿/hour/guard rate as an exact decimal STRING ("500.00"). The client never
  /// sets it; it arrives on the created booking and drives the authoritative charge amount.
  final String? baseFee;

  /// Flat tip chosen on the booking form, exact decimal STRING ("0"); under post-pay it is billed
  /// in full on completion (never prorated).
  final String? tip;

  /// Optional site coordinate (WGS84) the customer pinned on the map at create time; `null`
  /// when no map pick was made. Lets the guard see the job location (e.g. on a map/navigation).
  final double? lat;
  final double? lng;

  /// When the booking's PRE-PAY charge cleared — set server-side once the booking service
  /// consumes `pguard.events.payment.completed`. `null` until paid. THE payment gate: the
  /// guard's `en_route` (and everything after) requires this to be non-null — the backend 409s
  /// the transition while it is null, and the UI mirrors that by disabling the action. Both the
  /// customer (route to PaymentScreen on `accepted` while unpaid) and the guard ("รอลูกค้าชำระเงิน"
  /// until paid) read it from the GET `/bookings/{id}` snapshot (the WS frame carries only the
  /// status, so a freshly-paid booking surfaces this on the next snapshot — and it is carried
  /// forward across WS frames by [applyEvent]).
  final DateTime? paidAt;

  /// Whether the PRE-PAY charge has cleared — `true` once [paidAt] is set. Gates the guard's
  /// start action and the customer's "waiting for the guard" state.
  bool get isPaid => paidAt != null;

  /// When the guard actually started work (server-stamped by `PUT /bookings/{id}/start`, the
  /// proration basis). `null` until started — and on snapshots from a backend predating the
  /// field. The AUTHORITATIVE anchor for the active-job countdown + check-in schedule: with it,
  /// the work clock survives app restart/logout instead of re-deriving from check-in
  /// timestamps or a client-only stamp.
  final DateTime? workStartedAt;

  /// DISPLAY-only charge estimate in satang — `base_fee × hours × guard_count + tip` — derived
  /// purely from this snapshot's server-owned fields (the same figure the customer's live screen
  /// shows). `null` when the rate/hours aren't known yet (a fresh `requested` snapshot), so a
  /// caller can omit the total rather than print ฿0. NOT authoritative: the payment service
  /// re-computes + verifies the real charge (see [Money]). Reused by BOTH the customer's
  /// booking-details sheet and the guard's active-job details sheet so they never drift.
  int? get displayTotalSatang {
    final baseFeeSatang = Money.satangFromString(baseFee);
    final h = hours ?? 0;
    if (baseFeeSatang <= 0 || h <= 0) return null;
    return Money.total(
      baseFeeSatang: baseFeeSatang,
      hours: h,
      guardCount: guardCount ?? 1,
      tipSatang: Money.satangFromString(tip),
    );
  }

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        customerId: json['customer_id'] as String,
        guardId: json['guard_id'] as String?,
        status: BookingStatus.tryParse(json['status'] as String?) ??
            BookingStatus.requested,
        address: json['address'] as String?,
        scheduledAt: json['scheduled_at'] != null
            ? DateTime.tryParse(json['scheduled_at'] as String)
            : null,
        hours: (json['hours'] as num?)?.toInt(),
        guardCount: (json['guard_count'] as num?)?.toInt(),
        // Money fields are decimal strings on the wire; parse defensively.
        baseFee: (json['base_fee'] as Object?)?.toString(),
        tip: (json['tip'] as Object?)?.toString(),
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        paidAt: json['paid_at'] != null
            ? DateTime.tryParse(json['paid_at'] as String)
            : null,
        workStartedAt: json['work_started_at'] != null
            ? DateTime.tryParse(json['work_started_at'] as String)
            : null,
      );

  /// A copy with [paidAt] set (everything else unchanged). Used to OPTIMISTICALLY mark a booking
  /// paid the instant the customer's charge clears, before the booking service's async `paid_at`
  /// lands — and to CARRY a known `paidAt` forward onto a fresh snapshot that lacks one. Keeps
  /// `paid` monotonic (the live controller never passes a null here).
  Booking withPaidAt(DateTime paidAt) => Booking(
        id: id,
        customerId: customerId,
        guardId: guardId,
        status: status,
        address: address,
        scheduledAt: scheduledAt,
        hours: hours,
        guardCount: guardCount,
        baseFee: baseFee,
        tip: tip,
        lat: lat,
        lng: lng,
        paidAt: paidAt,
        workStartedAt: workStartedAt,
      );

  /// A copy with the status advanced by a real-time event (and guard id filled if newly known).
  /// [paidAt] is CARRIED FORWARD (the WS frame has no payment field) so a booking already known
  /// to be paid stays paid as later status frames arrive.
  ///
  /// A REFRESH-ONLY event (a guard check-in nudge — [BookingStatusEvent.status] is null) carries NO
  /// status change: the current [status] is kept. The returned copy is still a FRESH instance, so
  /// re-emitting it notifies dependents (the progress-reports controller re-pulls the new check-in
  /// photo + the advancing countdown) WITHOUT rewinding the booking's lifecycle status.
  Booking applyEvent(BookingStatusEvent event) => Booking(
        id: id,
        customerId: customerId,
        guardId: event.guardId ?? guardId,
        status: event.status ?? status,
        address: address,
        scheduledAt: scheduledAt,
        hours: hours,
        guardCount: guardCount,
        baseFee: baseFee,
        tip: tip,
        lat: lat,
        lng: lng,
        paidAt: paidAt,
        workStartedAt: workStartedAt,
      );
}

/// Pure lifecycle helper: the ordered customer-visible steps + classification of any status.
/// Drives the live-status stepper without any timer/polling.
class BookingLifecycle {
  const BookingLifecycle._();

  /// The forward "happy path" steps shown in the stepper, in order.
  static const List<BookingStatus> steps = [
    BookingStatus.accepted,
    BookingStatus.enRoute,
    BookingStatus.arrived,
    BookingStatus.pendingCompletion,
    BookingStatus.completed,
  ];

  /// Index of [status] within [steps]; `-1` for `requested` (before step 0) and for the
  /// negative-terminal states (`declined`/`cancelled`), which the UI renders distinctly.
  static int stepIndex(BookingStatus status) => steps.indexOf(status);

  /// `true` once no further transitions are possible.
  static bool isTerminal(BookingStatus status) =>
      status == BookingStatus.completed ||
      status == BookingStatus.declined ||
      status == BookingStatus.cancelled;

  /// `true` for the negative terminals (job will not proceed).
  static bool isNegativeTerminal(BookingStatus status) =>
      status == BookingStatus.declined || status == BookingStatus.cancelled;

  /// Whether a guard is assigned and actively progressing (post-accept, pre-terminal).
  static bool isActive(BookingStatus status) =>
      stepIndex(status) >= 0 && status != BookingStatus.completed;

  /// Whether the guard is in the GPS-streaming window: en route → arrived → awaiting completion.
  /// Deliberately NARROWER than [isActive]: a merely-`accepted` job is NOT streaming yet (a standby
  /// guard may just be viewing the offer), so we DON'T take the location lease / prompt for the OS
  /// location permission until the guard has actually started the journey (`en_route`) or later.
  /// The customer's live map only needs the guard's position once the guard is on the way.
  static bool isStreaming(BookingStatus status) =>
      status == BookingStatus.enRoute ||
      status == BookingStatus.arrived ||
      status == BookingStatus.pendingCompletion;

  /// Whether a live voice/video call is allowed for this booking. Mirrors the calling service's
  /// `is_callable_status` EXACTLY (`accepted | en_route | arrived`) — a guard has accepted and the
  /// job is in flight. Deliberately NARROWER than [isActive]: `pendingCompletion` is active but the
  /// calling service rejects it (409 "Booking is not in an active state for calling"), so the call
  /// UI must gate on this, never on [isActive], to avoid routing into a guaranteed error.
  /// See `services/calling/src/domain/mod.rs::is_callable_status`.
  static bool isCallable(BookingStatus status) =>
      status == BookingStatus.accepted ||
      status == BookingStatus.enRoute ||
      status == BookingStatus.arrived;

  /// Bilingual short label for a status (TH primary, EN secondary).
  static String labelTh(BookingStatus status) {
    switch (status) {
      case BookingStatus.requested:
        return 'กำลังค้นหาเจ้าหน้าที่';
      case BookingStatus.accepted:
        return 'รับงานแล้ว';
      case BookingStatus.enRoute:
        return 'กำลังเดินทาง';
      case BookingStatus.arrived:
        return 'ถึงจุดนัดหมาย';
      case BookingStatus.pendingCompletion:
        return 'รอยืนยันจบงาน';
      case BookingStatus.completed:
        return 'เสร็จสิ้น';
      case BookingStatus.declined:
        return 'เจ้าหน้าที่ปฏิเสธ';
      case BookingStatus.cancelled:
        return 'ยกเลิกแล้ว';
    }
  }

  /// Bilingual short label for a status (EN).
  static String labelEn(BookingStatus status) {
    switch (status) {
      case BookingStatus.requested:
        return 'Finding a guard';
      case BookingStatus.accepted:
        return 'Guard assigned';
      case BookingStatus.enRoute:
        return 'On the way';
      case BookingStatus.arrived:
        return 'Arrived';
      case BookingStatus.pendingCompletion:
        return 'Awaiting your confirmation';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.declined:
        return 'Guard declined';
      case BookingStatus.cancelled:
        return 'Cancelled';
    }
  }
}
