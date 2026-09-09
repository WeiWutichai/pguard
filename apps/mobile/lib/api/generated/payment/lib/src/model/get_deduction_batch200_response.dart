//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/deduction_batch_detail.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_deduction_batch200_response.g.dart';

/// GetDeductionBatch200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetDeductionBatch200Response implements ApiResponseEnvelope, Built<GetDeductionBatch200Response, GetDeductionBatch200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  DeductionBatchDetail? get data;

  GetDeductionBatch200Response._();

  factory GetDeductionBatch200Response([void updates(GetDeductionBatch200ResponseBuilder b)]) = _$GetDeductionBatch200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetDeductionBatch200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetDeductionBatch200Response> get serializer => _$GetDeductionBatch200ResponseSerializer();
}

class _$GetDeductionBatch200ResponseSerializer implements PrimitiveSerializer<GetDeductionBatch200Response> {
  @override
  final Iterable<Type> types = const [GetDeductionBatch200Response, _$GetDeductionBatch200Response];

  @override
  final String wireName = r'GetDeductionBatch200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetDeductionBatch200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(DeductionBatchDetail),
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
    GetDeductionBatch200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetDeductionBatch200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DeductionBatchDetail),
          ) as DeductionBatchDetail;
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
  GetDeductionBatch200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetDeductionBatch200ResponseBuilder();
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

