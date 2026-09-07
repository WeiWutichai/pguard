//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'void_refund_batch_request.g.dart';

/// VoidRefundBatchRequest
///
/// Properties:
/// * [reason] - Why the batch is being voided. Must be non-blank — the void returns every obligation in it to the refundable queue.
@BuiltValue()
abstract class VoidRefundBatchRequest implements Built<VoidRefundBatchRequest, VoidRefundBatchRequestBuilder> {
  /// Why the batch is being voided. Must be non-blank — the void returns every obligation in it to the refundable queue.
  @BuiltValueField(wireName: r'reason')
  String get reason;

  VoidRefundBatchRequest._();

  factory VoidRefundBatchRequest([void updates(VoidRefundBatchRequestBuilder b)]) = _$VoidRefundBatchRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VoidRefundBatchRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VoidRefundBatchRequest> get serializer => _$VoidRefundBatchRequestSerializer();
}

class _$VoidRefundBatchRequestSerializer implements PrimitiveSerializer<VoidRefundBatchRequest> {
  @override
  final Iterable<Type> types = const [VoidRefundBatchRequest, _$VoidRefundBatchRequest];

  @override
  final String wireName = r'VoidRefundBatchRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VoidRefundBatchRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    VoidRefundBatchRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VoidRefundBatchRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  VoidRefundBatchRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VoidRefundBatchRequestBuilder();
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

