//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'payout_batch_item.g.dart';

/// One booking PAID by this batch (the paid-marker). `voided_at` set = the batch was voided and this booking is back in the payable backlog; the row is kept as history rather than deleted. 
///
/// Properties:
/// * [id] 
/// * [bookingId] 
/// * [guardId] 
/// * [income] - base_fee × actual_hours − commission (2dp string).
/// * [wht] - Withholding tax for this booking (2dp string).
/// * [transferAmount] - income − wht (2dp string).
/// * [voidedAt] 
/// * [createdAt] 
@BuiltValue()
abstract class PayoutBatchItem implements Built<PayoutBatchItem, PayoutBatchItemBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  /// base_fee × actual_hours − commission (2dp string).
  @BuiltValueField(wireName: r'income')
  String get income;

  /// Withholding tax for this booking (2dp string).
  @BuiltValueField(wireName: r'wht')
  String get wht;

  /// income − wht (2dp string).
  @BuiltValueField(wireName: r'transfer_amount')
  String get transferAmount;

  @BuiltValueField(wireName: r'voided_at')
  DateTime? get voidedAt;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  PayoutBatchItem._();

  factory PayoutBatchItem([void updates(PayoutBatchItemBuilder b)]) = _$PayoutBatchItem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PayoutBatchItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PayoutBatchItem> get serializer => _$PayoutBatchItemSerializer();
}

class _$PayoutBatchItemSerializer implements PrimitiveSerializer<PayoutBatchItem> {
  @override
  final Iterable<Type> types = const [PayoutBatchItem, _$PayoutBatchItem];

  @override
  final String wireName = r'PayoutBatchItem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PayoutBatchItem object, {
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
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    yield r'income';
    yield serializers.serialize(
      object.income,
      specifiedType: const FullType(String),
    );
    yield r'wht';
    yield serializers.serialize(
      object.wht,
      specifiedType: const FullType(String),
    );
    yield r'transfer_amount';
    yield serializers.serialize(
      object.transferAmount,
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
    PayoutBatchItem object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PayoutBatchItemBuilder result,
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
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'income':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.income = valueDes;
          break;
        case r'wht':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.wht = valueDes;
          break;
        case r'transfer_amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.transferAmount = valueDes;
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
  PayoutBatchItem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PayoutBatchItemBuilder();
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

