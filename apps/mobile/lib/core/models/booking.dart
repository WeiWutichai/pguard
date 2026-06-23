// Booking domain model + the lifecycle state machine the live-status UI renders.
//
// Mirrors the backend `booking.booking_status` enum (contracts/openapi/booking.yaml). The
// lifecycle helpers (BookingLifecycle) are PURE (no Flutter imports) so the stepper logic
// is unit-testable; colors live in the widget layer.

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

/// One real-time status transition pushed over the booking-status WebSocket.
/// Envelope (documented contract — see booking_status_socket.dart):
/// `{ "type":"booking_status", "booking_id", "status", "occurred_at", "guard_id"? }`.
class BookingStatusEvent {
  const BookingStatusEvent({
    required this.bookingId,
    required this.status,
    required this.occurredAt,
    this.guardId,
  });

  final String bookingId;
  final BookingStatus status;
  final DateTime occurredAt;
  final String? guardId;

  /// Parse a decoded WS frame; returns `null` if it is not a well-formed `booking_status`
  /// message (so the socket can ignore heartbeats / unknown frames).
  static BookingStatusEvent? tryParse(Map<String, dynamic> json) {
    if (json['type'] != 'booking_status') return null;
    final status = BookingStatus.tryParse(json['status'] as String?);
    final bookingId = json['booking_id'] as String?;
    if (status == null || bookingId == null) return null;
    final occurredRaw = json['occurred_at'] as String?;
    final occurredAt =
        (occurredRaw != null ? DateTime.tryParse(occurredRaw) : null)
                ?.toUtc() ??
            DateTime.now().toUtc();
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
      );

  /// A copy with the status advanced by a real-time event (and guard id filled if newly known).
  Booking applyEvent(BookingStatusEvent event) => Booking(
        id: id,
        customerId: customerId,
        guardId: event.guardId ?? guardId,
        status: event.status,
        address: address,
        scheduledAt: scheduledAt,
        hours: hours,
        guardCount: guardCount,
        baseFee: baseFee,
        tip: tip,
        lat: lat,
        lng: lng,
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
