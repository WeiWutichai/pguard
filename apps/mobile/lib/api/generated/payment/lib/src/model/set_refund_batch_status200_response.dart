//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/refund_batch.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_refund_batch_status200_response.g.dart';

/// SetRefundBatchStatus200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class SetRefundBatchStatus200Response implements ApiResponseEnvelope, Built<SetRefundBatchStatus200Response, SetRefundBatchStatus200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  RefundBatch? get data;

  SetRefundBatchStatus200Response._();

  factory SetRefundBatchStatus200Response([void updates(SetRefundBatchStatus200ResponseBuilder b)]) = _$SetRefundBatchStatus200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetRefundBatchStatus200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetRefundBatchStatus200Response> get serializer => _$SetRefundBatchStatus200ResponseSerializer();
}

class _$SetRefundBatchStatus200ResponseSerializer implements PrimitiveSerializer<SetRefundBatchStatus200Response> {
  @override
  final Iterable<Type> types = const [SetRefundBatchStatus200Response, _$SetRefundBatchStatus200Response];

  @override
  final String wireName = r'SetRefundBatchStatus200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetRefundBatchStatus200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(RefundBatch),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
    yield r'success';
    yield serializers.serialize(
      object.success,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SetRefundBatchStatus200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetRefundBatchStatus200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RefundBatch),
          ) as RefundBatch;
          result.data = valueDes;
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SetRefundBatchStatus200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetRefundBatchStatus200ResponseBuilder();
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

