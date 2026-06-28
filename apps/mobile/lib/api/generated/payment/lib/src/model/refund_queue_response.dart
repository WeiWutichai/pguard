//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/refund_queue_item.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refund_queue_response.g.dart';

/// The refund-queue page (newest first) + the total count matching the same filter.
///
/// Properties:
/// * [refunds] 
/// * [count] - Total refund rows matching the filter (independent of limit/offset) — the badge count.
@BuiltValue()
abstract class RefundQueueResponse implements Built<RefundQueueResponse, RefundQueueResponseBuilder> {
  @BuiltValueField(wireName: r'refunds')
  BuiltList<RefundQueueItem> get refunds;

  /// Total refund rows matching the filter (independent of limit/offset) — the badge count.
  @BuiltValueField(wireName: r'count')
  int get count;

  RefundQueueResponse._();

  factory RefundQueueResponse([void updates(RefundQueueResponseBuilder b)]) = _$RefundQueueResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RefundQueueResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RefundQueueResponse> get serializer => _$RefundQueueResponseSerializer();
}

class _$RefundQueueResponseSerializer implements PrimitiveSerializer<RefundQueueResponse> {
  @override
  final Iterable<Type> types = const [RefundQueueResponse, _$RefundQueueResponse];

  @override
  final String wireName = r'RefundQueueResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RefundQueueResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'refunds';
    yield serializers.serialize(
      object.refunds,
      specifiedType: const FullType(BuiltList, [FullType(RefundQueueItem)]),
    );
    yield r'count';
    yield serializers.serialize(
      object.count,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RefundQueueResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RefundQueueResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'refunds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RefundQueueItem)]),
          ) as BuiltList<RefundQueueItem>;
          result.refunds.replace(valueDes);
          break;
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RefundQueueResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RefundQueueResponseBuilder();
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

