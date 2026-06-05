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

/// The customer-selectable payment methods (contract enum + bilingual labels).
enum PaymentMethod {
  promptpay('promptpay', 'พร้อมเพย์', 'PromptPay'),
  creditCard('credit_card', 'บัตรเครดิต', 'Credit card'),
  debitCard('debit_card', 'บัตรเดบิต', 'Debit card'),
  mobileBanking('mobile_banking', 'โมบายแบงก์กิ้ง', 'Mobile banking');

  const PaymentMethod(this.wire, this.labelTh, this.labelEn);

  /// The value sent in `payment_method`.
  final String wire;
  final String labelTh;
  final String labelEn;
}

/// A payment as returned by `POST /v1/payments` (money fields are decimal STRINGS).
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
    this.paidAt,
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
  final PaymentStatus status;
  final DateTime? paidAt;

  bool get isCompleted => status == PaymentStatus.completed;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        bookingId: json['booking_id'] as String,
        customerId: json['customer_id'] as String,
        guardId: json['guard_id'] as String?,
        amount: json['amount'] as String,
        expectedTotal: json['expected_total'] as String?,
        paymentMethod: json['payment_method'] as String?,
        status: PaymentStatus.tryParse(json['status'] as String?) ??
            PaymentStatus.pending,
        paidAt: json['paid_at'] != null
            ? DateTime.tryParse(json['paid_at'] as String)
            : null,
      );
}
