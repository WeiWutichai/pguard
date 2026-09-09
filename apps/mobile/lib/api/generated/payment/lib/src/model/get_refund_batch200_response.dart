//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/refund_batch_detail.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_refund_batch200_response.g.dart';

/// GetRefundBatch200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetRefundBatch200Response implements ApiResponseEnvelope, Built<GetRefundBatch200Response, GetRefundBatch200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  RefundBatchDetail? get data;

  GetRefundBatch200Response._();

  factory GetRefundBatch200Response([void updates(GetRefundBatch200ResponseBuilder b)]) = _$GetRefundBatch200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetRefundBatch200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetRefundBatch200Response> get serializer => _$GetRefundBatch200ResponseSerializer();
}

class _$GetRefundBatch200ResponseSerializer implements PrimitiveSerializer<GetRefundBatch200Response> {
  @override
  final Iterable<Type> types = const [GetRefundBatch200Response, _$GetRefundBatch200Response];

  @override
  final String wireName = r'GetRefundBatch200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetRefundBatch200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(RefundBatchDetail),
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
    GetRefundBatch200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetRefundBatch200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RefundBatchDetail),
          ) as RefundBatchDetail;
          result.data.replace(valueDes);
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
  GetRefundBatch200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetRefundBatch200ResponseBuilder();
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

