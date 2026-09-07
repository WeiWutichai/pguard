//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'void_deduction_batch_request.g.dart';

/// VoidDeductionBatchRequest
///
/// Properties:
/// * [reason] - REQUIRED and non-blank. A void returns every job in the batch to the sweepable backlog, and six months later \"voided\" with no reason cannot be told apart from a mis-click. Max 500 characters. 
@BuiltValue()
abstract class VoidDeductionBatchRequest implements Built<VoidDeductionBatchRequest, VoidDeductionBatchRequestBuilder> {
  /// REQUIRED and non-blank. A void returns every job in the batch to the sweepable backlog, and six months later \"voided\" with no reason cannot be told apart from a mis-click. Max 500 characters. 
  @BuiltValueField(wireName: r'reason')
  String get reason;

  VoidDeductionBatchRequest._();

  factory VoidDeductionBatchRequest([void updates(VoidDeductionBatchRequestBuilder b)]) = _$VoidDeductionBatchRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VoidDeductionBatchRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VoidDeductionBatchRequest> get serializer => _$VoidDeductionBatchRequestSerializer();
}

class _$VoidDeductionBatchRequestSerializer implements PrimitiveSerializer<VoidDeductionBatchRequest> {
  @override
  final Iterable<Type> types = const [VoidDeductionBatchRequest, _$VoidDeductionBatchRequest];

  @override
  final String wireName = r'VoidDeductionBatchRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VoidDeductionBatchRequest object, {
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
    VoidDeductionBatchRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VoidDeductionBatchRequestBuilder result,
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
  VoidDeductionBatchRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VoidDeductionBatchRequestBuilder();
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

