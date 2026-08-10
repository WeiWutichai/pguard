//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/payment_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'payment.g.dart';

/// One booking's charge. MONEY VOCABULARY (all exact decimal strings; VAT rate 7%):   subtotal    = base_fee × hours × guard_count + tip   ← VAT-EXCLUSIVE, the catalog price   vat_amount  = subtotal × 0.07   grand_total = subtotal + vat_amount                  ← what the customer actually pays `amount` (what was pre-paid) is the VAT-INCLUSIVE `grand_total`, not the subtotal — the catalog's rates are quoted before VAT, so the charge is higher than base_fee × hours. 
///
/// Properties:
/// * [id] 
/// * [bookingId] 
/// * [customerId] 
/// * [guardId] 
/// * [amount] - Exact decimal PRE-PAID — the VAT-INCLUSIVE grand total. Never re-charged on settle.
/// * [expectedTotal] - Server-computed authoritative charge at pre-pay time — the VAT-INCLUSIVE total ((base_fee × hours × guards + tip) + VAT 7%), i.e. the same figure as `grand_total`.
/// * [subtotal] - VAT-EXCLUSIVE service cost of the CURRENTLY SETTLED bill — base_fee × hours × guard_count + tip (booked hours until the completion settle, actual hours after). This is the \"ราคาสินค้า/บริการ\" line of the tax invoice, NOT what the customer pays. null on payments taken before VAT was itemized (their `amount` was the whole charge, VAT-free).
/// * [vatAmount] - VAT charged ON TOP of `subtotal` at 7% (`subtotal × 0.07`, rounded to 2dp) — the \"ภาษีมูลค่าเพิ่ม 7%\" line of the tax invoice. Collected for the Revenue Department, so it is NOT platform revenue. null on pre-VAT payments.
/// * [grandTotal] - `subtotal + vat_amount` — the VAT-INCLUSIVE amount the customer owes, and the \"จำนวนเงินรวมทั้งสิ้น\" line of the tax invoice. ALWAYS present (unlike the two fields it is made of): on a pre-VAT row it falls back to `amount`, so this is the payable figure for every payment ever taken. Tracks the SETTLED bill — it follows `final_amount` once the actual hours are reconciled, and equals `amount` until then.
/// * [cancellationFeeCharged] - What was actually KEPT as a cancellation fee when the CUSTOMER cancelled before work started: `min(booking.cancellation_fee, amount_paid)` — capped at what was paid, so a cancellation can never leave the customer owing money (nothing paid → nothing charged, `\"0.00\"`). The refund is `amount_paid − cancellation_fee_charged`. Stays null/`\"0.00\"` when the GUARD withdrew (not the customer's fault → full refund) and on jobs that were never cancelled.
/// * [paymentMethod] - How the charge settled: `prepaid` (simulated gateway) or `promptpay_slip` (real Slip2Go-verified transfer).
/// * [status] 
/// * [finalAmount] - The reconciled actual-hours bill, set on the completion SETTLE (null until then). May be less than `amount` (overpay refunded) or more (shortfall recorded).
/// * [refundAmount] - The overpay returned to the customer on the SETTLE when actual hours < pre-paid (null when none owed).
/// * [actualHours] - Clamped hours actually worked, recorded on the settle.
/// * [refundStatus] - `pending` once a settle refund is owed (an admin/real-gateway marks `processed`); null when no refund.
/// * [paidAt] 
/// * [createdAt] 
/// * [updatedAt] 
@BuiltValue()
abstract class Payment implements Built<Payment, PaymentBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  @BuiltValueField(wireName: r'customer_id')
  String get customerId;

  @BuiltValueField(wireName: r'guard_id')
  String? get guardId;

  /// Exact decimal PRE-PAID — the VAT-INCLUSIVE grand total. Never re-charged on settle.
  @BuiltValueField(wireName: r'amount')
  String get amount;

  /// Server-computed authoritative charge at pre-pay time — the VAT-INCLUSIVE total ((base_fee × hours × guards + tip) + VAT 7%), i.e. the same figure as `grand_total`.
  @BuiltValueField(wireName: r'expected_total')
  String? get expectedTotal;

  /// VAT-EXCLUSIVE service cost of the CURRENTLY SETTLED bill — base_fee × hours × guard_count + tip (booked hours until the completion settle, actual hours after). This is the \"ราคาสินค้า/บริการ\" line of the tax invoice, NOT what the customer pays. null on payments taken before VAT was itemized (their `amount` was the whole charge, VAT-free).
  @BuiltValueField(wireName: r'subtotal')
  String? get subtotal;

  /// VAT charged ON TOP of `subtotal` at 7% (`subtotal × 0.07`, rounded to 2dp) — the \"ภาษีมูลค่าเพิ่ม 7%\" line of the tax invoice. Collected for the Revenue Department, so it is NOT platform revenue. null on pre-VAT payments.
  @BuiltValueField(wireName: r'vat_amount')
  String? get vatAmount;

  /// `subtotal + vat_amount` — the VAT-INCLUSIVE amount the customer owes, and the \"จำนวนเงินรวมทั้งสิ้น\" line of the tax invoice. ALWAYS present (unlike the two fields it is made of): on a pre-VAT row it falls back to `amount`, so this is the payable figure for every payment ever taken. Tracks the SETTLED bill — it follows `final_amount` once the actual hours are reconciled, and equals `amount` until then.
  @BuiltValueField(wireName: r'grand_total')
  String get grandTotal;

  /// What was actually KEPT as a cancellation fee when the CUSTOMER cancelled before work started: `min(booking.cancellation_fee, amount_paid)` — capped at what was paid, so a cancellation can never leave the customer owing money (nothing paid → nothing charged, `\"0.00\"`). The refund is `amount_paid − cancellation_fee_charged`. Stays null/`\"0.00\"` when the GUARD withdrew (not the customer's fault → full refund) and on jobs that were never cancelled.
  @BuiltValueField(wireName: r'cancellation_fee_charged')
  String? get cancellationFeeCharged;

  /// How the charge settled: `prepaid` (simulated gateway) or `promptpay_slip` (real Slip2Go-verified transfer).
  @BuiltValueField(wireName: r'payment_method')
  String? get paymentMethod;

  @BuiltValueField(wireName: r'status')
  PaymentStatus get status;
  // enum statusEnum {  pending,  completed,  refunded,  };

  /// The reconciled actual-hours bill, set on the completion SETTLE (null until then). May be less than `amount` (overpay refunded) or more (shortfall recorded).
  @BuiltValueField(wireName: r'final_amount')
  String? get finalAmount;

  /// The overpay returned to the customer on the SETTLE when actual hours < pre-paid (null when none owed).
  @BuiltValueField(wireName: r'refund_amount')
  String? get refundAmount;

  /// Clamped hours actually worked, recorded on the settle.
  @BuiltValueField(wireName: r'actual_hours')
  String? get actualHours;

  /// `pending` once a settle refund is owed (an admin/real-gateway marks `processed`); null when no refund.
  @BuiltValueField(wireName: r'refund_status')
  PaymentRefundStatusEnum? get refundStatus;
  // enum refundStatusEnum {  pending,  processed,  };

  @BuiltValueField(wireName: r'paid_at')
  DateTime? get paidAt;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  Payment._();

  factory Payment([void updates(PaymentBuilder b)]) = _$Payment;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PaymentBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Payment> get serializer => _$PaymentSerializer();
}

class _$PaymentSerializer implements PrimitiveSerializer<Payment> {
  @override
  final Iterable<Type> types = const [Payment, _$Payment];

  @override
  final String wireName = r'Payment';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Payment object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'booking_id';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
    yield r'customer_id';
    yield serializers.serialize(
      object.customerId,
      specifiedType: const FullType(String),
    );
    if (object.guardId != null) {
      yield r'guard_id';
      yield serializers.serialize(
        object.guardId,
        specifiedType: const FullType(String),
      );
    }
    yield r'amount';
    yield serializers.serialize(
      object.amount,
      specifiedType: const FullType(String),
    );
    if (object.expectedTotal != null) {
      yield r'expected_total';
      yield serializers.serialize(
        object.expectedTotal,
        specifiedType: const FullType(String),
      );
    }
    if (object.subtotal != null) {
      yield r'subtotal';
      yield serializers.serialize(
        object.subtotal,
        specifiedType: const FullType(String),
      );
    }
    if (object.vatAmount != null) {
      yield r'vat_amount';
      yield serializers.serialize(
        object.vatAmount,
        specifiedType: const FullType(String),
      );
    }
    yield r'grand_total';
    yield serializers.serialize(
      object.grandTotal,
      specifiedType: const FullType(String),
    );
    if (object.cancellationFeeCharged != null) {
      yield r'cancellation_fee_charged';
      yield serializers.serialize(
        object.cancellationFeeCharged,
        specifiedType: const FullType(String),
      );
    }
    if (object.paymentMethod != null) {
      yield r'payment_method';
      yield serializers.serialize(
        object.paymentMethod,
        specifiedType: const FullType(String),
      );
    }
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(PaymentStatus),
    );
    if (object.finalAmount != null) {
      yield r'final_amount';
      yield serializers.serialize(
        object.finalAmount,
        specifiedType: const FullType(String),
      );
    }
    if (object.refundAmount != null) {
      yield r'refund_amount';
      yield serializers.serialize(
        object.refundAmount,
        specifiedType: const FullType(String),
      );
    }
    if (object.actualHours != null) {
      yield r'actual_hours';
      yield serializers.serialize(
        object.actualHours,
        specifiedType: const FullType(String),
      );
    }
    if (object.refundStatus != null) {
      yield r'refund_status';
      yield serializers.serialize(
        object.refundStatus,
        specifiedType: const FullType(PaymentRefundStatusEnum),
      );
    }
    if (object.paidAt != null) {
      yield r'paid_at';
      yield serializers.serialize(
        object.paidAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'updated_at';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Payment object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PaymentBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'customer_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.customerId = valueDes;
          break;
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.amount = valueDes;
          break;
        case r'expected_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.expectedTotal = valueDes;
          break;
        case r'subtotal':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.subtotal = valueDes;
          break;
        case r'vat_amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.vatAmount = valueDes;
          break;
        case r'grand_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.grandTotal = valueDes;
          break;
        case r'cancellation_fee_charged':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cancellationFeeCharged = valueDes;
          break;
        case r'payment_method':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.paymentMethod = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PaymentStatus),
          ) as PaymentStatus;
          result.status = valueDes;
          break;
        case r'final_amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.finalAmount = valueDes;
          break;
        case r'refund_amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.refundAmount = valueDes;
          break;
        case r'actual_hours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.actualHours = valueDes;
          break;
        case r'refund_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PaymentRefundStatusEnum),
          ) as PaymentRefundStatusEnum;
          result.refundStatus = valueDes;
          break;
        case r'paid_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.paidAt = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Payment deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PaymentBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

class PaymentRefundStatusEnum extends EnumClass {

  /// `pending` once a settle refund is owed (an admin/real-gateway marks `processed`); null when no refund.
  @BuiltValueEnumConst(wireName: r'pending')
  static const PaymentRefundStatusEnum pending = _$paymentRefundStatusEnum_pending;
  /// `pending` once a settle refund is owed (an admin/real-gateway marks `processed`); null when no refund.
  @BuiltValueEnumConst(wireName: r'processed')
  static const PaymentRefundStatusEnum processed = _$paymentRefundStatusEnum_processed;

  static Serializer<PaymentRefundStatusEnum> get serializer => _$paymentRefundStatusEnumSerializer;

  const PaymentRefundStatusEnum._(String name): super(name);

  static BuiltSet<PaymentRefundStatusEnum> get values => _$paymentRefundStatusEnumValues;
  static PaymentRefundStatusEnum valueOf(String name) => _$paymentRefundStatusEnumValueOf(name);
}

