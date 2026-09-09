//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'void_payout_batch_request.g.dart';

/// VoidPayoutBatchRequest
///
/// Properties:
/// * [reason] - Why the batch is being voided. Must be non-blank — the void returns every booking in it to the payable backlog.
@BuiltValue()
abstract class VoidPayoutBatchRequest implements Built<VoidPayoutBatchRequest, VoidPayoutBatchRequestBuilder> {
  /// Why the batch is being voided. Must be non-blank — the void returns every booking in it to the payable backlog.
  @BuiltValueField(wireName: r'reason')
  String get reason;

  VoidPayoutBatchRequest._();

  factory VoidPayoutBatchRequest([void updates(VoidPayoutBatchRequestBuilder b)]) = _$VoidPayoutBatchRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VoidPayoutBatchRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VoidPayoutBatchRequest> get serializer => _$VoidPayoutBatchRequestSerializer();
}

class _$VoidPayoutBatchRequestSerializer implements PrimitiveSerializer<VoidPayoutBatchRequest> {
  @override
  final Iterable<Type> types = const [VoidPayoutBatchRequest, _$VoidPayoutBatchRequest];

  @override
  final String wireName = r'VoidPayoutBatchRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VoidPayoutBatchRequest object, {
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
    VoidPayoutBatchRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VoidPayoutBatchRequestBuilder result,
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
  VoidPayoutBatchRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VoidPayoutBatchRequestBuilder();
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

