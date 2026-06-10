//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/payment_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'payment.g.dart';

/// Payment
///
/// Properties:
/// * [id] 
/// * [bookingId] 
/// * [customerId] 
/// * [guardId] 
/// * [amount] - Exact decimal charged
/// * [expectedTotal] - Server-computed authoritative total at charge time (base_fee × hours × guards + tip).
/// * [paymentMethod] 
/// * [status] 
/// * [finalAmount] - Prorated amount after completion
/// * [refundAmount] - Amount returned to the customer
/// * [actualHours] - Clamped hours actually worked
/// * [refundStatus] - Set to `pending` when a refund is owed (admin marks `processed` later); else null.
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

  /// Exact decimal charged
  @BuiltValueField(wireName: r'amount')
  String get amount;

  /// Server-computed authoritative total at charge time (base_fee × hours × guards + tip).
  @BuiltValueField(wireName: r'expected_total')
  String? get expectedTotal;

  @BuiltValueField(wireName: r'payment_method')
  String? get paymentMethod;

  @BuiltValueField(wireName: r'status')
  PaymentStatus get status;
  // enum statusEnum {  pending,  completed,  refunded,  };

  /// Prorated amount after completion
  @BuiltValueField(wireName: r'final_amount')
  String? get finalAmount;

  /// Amount returned to the customer
  @BuiltValueField(wireName: r'refund_amount')
  String? get refundAmount;

  /// Clamped hours actually worked
  @BuiltValueField(wireName: r'actual_hours')
  String? get actualHours;

  /// Set to `pending` when a refund is owed (admin marks `processed` later); else null.
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

  /// Set to `pending` when a refund is owed (admin marks `processed` later); else null.
  @BuiltValueEnumConst(wireName: r'pending')
  static const PaymentRefundStatusEnum pending = _$paymentRefundStatusEnum_pending;
  /// Set to `pending` when a refund is owed (admin marks `processed` later); else null.
  @BuiltValueEnumConst(wireName: r'processed')
  static const PaymentRefundStatusEnum processed = _$paymentRefundStatusEnum_processed;

  static Serializer<PaymentRefundStatusEnum> get serializer => _$paymentRefundStatusEnumSerializer;

  const PaymentRefundStatusEnum._(String name): super(name);

  static BuiltSet<PaymentRefundStatusEnum> get values => _$paymentRefundStatusEnumValues;
  static PaymentRefundStatusEnum valueOf(String name) => _$paymentRefundStatusEnumValueOf(name);
}

