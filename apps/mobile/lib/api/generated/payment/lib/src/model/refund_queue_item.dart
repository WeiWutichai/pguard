//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/refund_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refund_queue_item.g.dart';

/// One refund-queue row — a payment whose settle or cancellation left a refund owed. `amount` is the refund owed (NOT the original charge); `status` is the refund-workflow state. On a customer cancellation the row is already NET of the cancellation fee (`amount_paid − cancellation_fee_charged`); on a guard withdrawal it is the full amount paid. 
///
/// Properties:
/// * [paymentId] 
/// * [bookingId] 
/// * [amount] - The refund owed to the customer (exact decimal as a string; money rule) — already net of any `cancellation_fee_charged`, so this is exactly what is sent back.
/// * [status] 
/// * [createdAt] 
@BuiltValue()
abstract class RefundQueueItem implements Built<RefundQueueItem, RefundQueueItemBuilder> {
  @BuiltValueField(wireName: r'payment_id')
  String get paymentId;

  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  /// The refund owed to the customer (exact decimal as a string; money rule) — already net of any `cancellation_fee_charged`, so this is exactly what is sent back.
  @BuiltValueField(wireName: r'amount')
  String get amount;

  @BuiltValueField(wireName: r'status')
  RefundStatus get status;
  // enum statusEnum {  pending,  processed,  };

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  RefundQueueItem._();

  factory RefundQueueItem([void updates(RefundQueueItemBuilder b)]) = _$RefundQueueItem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RefundQueueItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RefundQueueItem> get serializer => _$RefundQueueItemSerializer();
}

class _$RefundQueueItemSerializer implements PrimitiveSerializer<RefundQueueItem> {
  @override
  final Iterable<Type> types = const [RefundQueueItem, _$RefundQueueItem];

  @override
  final String wireName = r'RefundQueueItem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RefundQueueItem object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'payment_id';
    yield serializers.serialize(
      object.paymentId,
      specifiedType: const FullType(String),
    );
    yield r'booking_id';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
    yield r'amount';
    yield serializers.serialize(
      object.amount,
      specifiedType: const FullType(String),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(RefundStatus),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RefundQueueItem object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RefundQueueItemBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'payment_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.paymentId = valueDes;
          break;
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.amount = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RefundStatus),
          ) as RefundStatus;
          result.status = valueDes;
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
  RefundQueueItem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RefundQueueItemBuilder();
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

