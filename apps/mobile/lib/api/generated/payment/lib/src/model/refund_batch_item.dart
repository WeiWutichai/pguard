//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/refund_source_kind.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refund_batch_item.g.dart';

/// One refund OBLIGATION settled by this batch (the paid-marker). `voided_at` set = the obligation was returned to the refundable queue and its source row is `pending` again; the row is kept as history rather than deleted. 
///
/// Properties:
/// * [id] 
/// * [sourceKind] 
/// * [sourceId] - The owing row — `payments.id` or `payment_slips.id`.
/// * [bookingId] - What the refund is for.
/// * [customerId] 
/// * [amount] - This obligation's share of the customer's transfer (2dp string).
/// * [voidedAt] 
/// * [createdAt] 
@BuiltValue()
abstract class RefundBatchItem implements Built<RefundBatchItem, RefundBatchItemBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'source_kind')
  RefundSourceKind get sourceKind;
  // enum sourceKindEnum {  payment,  slip,  };

  /// The owing row — `payments.id` or `payment_slips.id`.
  @BuiltValueField(wireName: r'source_id')
  String get sourceId;

  /// What the refund is for.
  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  @BuiltValueField(wireName: r'customer_id')
  String get customerId;

  /// This obligation's share of the customer's transfer (2dp string).
  @BuiltValueField(wireName: r'amount')
  String get amount;

  @BuiltValueField(wireName: r'voided_at')
  DateTime? get voidedAt;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  RefundBatchItem._();

  factory RefundBatchItem([void updates(RefundBatchItemBuilder b)]) = _$RefundBatchItem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RefundBatchItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RefundBatchItem> get serializer => _$RefundBatchItemSerializer();
}

class _$RefundBatchItemSerializer implements PrimitiveSerializer<RefundBatchItem> {
  @override
  final Iterable<Type> types = const [RefundBatchItem, _$RefundBatchItem];

  @override
  final String wireName = r'RefundBatchItem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RefundBatchItem object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'source_kind';
    yield serializers.serialize(
      object.sourceKind,
      specifiedType: const FullType(RefundSourceKind),
    );
    yield r'source_id';
    yield serializers.serialize(
      object.sourceId,
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
    yield r'amount';
    yield serializers.serialize(
      object.amount,
      specifiedType: const FullType(String),
    );
    if (object.voidedAt != null) {
      yield r'voided_at';
      yield serializers.serialize(
        object.voidedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RefundBatchItem object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RefundBatchItemBuilder result,
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
        case r'source_kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RefundSourceKind),
          ) as RefundSourceKind;
          result.sourceKind = valueDes;
          break;
        case r'source_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceId = valueDes;
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
        case r'amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.amount = valueDes;
          break;
        case r'voided_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.voidedAt = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RefundBatchItem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RefundBatchItemBuilder();
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

