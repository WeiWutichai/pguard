// Payment domain model — mirrors `contracts/openapi/payment.yaml` (THE MONEY PATH).
// Money fields are exact decimal STRINGS. Pure (no Flutter) → unit-testable.

/// Payment lifecycle status (snake_case wire values).
enum PaymentStatus {
  pending('pending'),
  completed('completed'),
  refunded('refunded');

  const PaymentStatus(this.wire);

  final String wire;

  static PaymentStatus? tryParse(String? value) {
    if (value == null) return null;
    for (final s in PaymentStatus.values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// A payment as returned by `GET /v1/payments` (post-pay: the bill is raised on completion; money
/// fields are decimal STRINGS). `payment_method` is a plain string (e.g. `post_paid`).
class Payment {
  const Payment({
    required this.id,
    required this.bookingId,
    required this.customerId,
    required this.amount,
    required this.status,
    this.guardId,
    this.expectedTotal,
    this.paymentMethod,
    this.finalAmount,
    this.refundAmount,
    this.paidAt,
    this.createdAt,
  });

  final String id;
  final String bookingId;
  final String customerId;
  final String? guardId;

  /// Exact amount charged (decimal string).
  final String amount;

  /// Server-computed authoritative total at charge time (base_fee × hours × guards + tip).
  final String? expectedTotal;
  final String? paymentMethod;

  /// Prorated amount after completion (decimal string) — what the customer ultimately pays
  /// once the booking finalizes; `null` until proration runs.
  final String? finalAmount;

  /// Amount returned to the customer (decimal string), when a refund is owed.
  final String? refundAmount;
  final PaymentStatus status;
  final DateTime? paidAt;
  final DateTime? createdAt;

  bool get isCompleted => status == PaymentStatus.completed;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        bookingId: json['booking_id'] as String,
        customerId: json['customer_id'] as String,
        guardId: json['guard_id'] as String?,
        // Money fields are decimal strings on the wire; parse defensively so a numeric type
        // from a misbehaving backend degrades gracefully instead of throwing.
        amount: (json['amount'] as Object?)?.toString() ?? '0',
        expectedTotal: (json['expected_total'] as Object?)?.toString(),
        paymentMethod: json['payment_method'] as String?,
        finalAmount: (json['final_amount'] as Object?)?.toString(),
        refundAmount: (json['refund_amount'] as Object?)?.toString(),
        status: PaymentStatus.tryParse(json['status'] as String?) ??
            PaymentStatus.pending,
        paidAt: json['paid_at'] != null
            ? DateTime.tryParse(json['paid_at'] as String)
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
      );
}
