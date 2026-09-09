//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/deduction_batch.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_deduction_batch_status200_response.g.dart';

/// SetDeductionBatchStatus200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class SetDeductionBatchStatus200Response implements ApiResponseEnvelope, Built<SetDeductionBatchStatus200Response, SetDeductionBatchStatus200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  DeductionBatch? get data;

  SetDeductionBatchStatus200Response._();

  factory SetDeductionBatchStatus200Response([void updates(SetDeductionBatchStatus200ResponseBuilder b)]) = _$SetDeductionBatchStatus200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetDeductionBatchStatus200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetDeductionBatchStatus200Response> get serializer => _$SetDeductionBatchStatus200ResponseSerializer();
}

class _$SetDeductionBatchStatus200ResponseSerializer implements PrimitiveSerializer<SetDeductionBatchStatus200Response> {
  @override
  final Iterable<Type> types = const [SetDeductionBatchStatus200Response, _$SetDeductionBatchStatus200Response];

  @override
  final String wireName = r'SetDeductionBatchStatus200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetDeductionBatchStatus200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(DeductionBatch),
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
    SetDeductionBatchStatus200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetDeductionBatchStatus200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DeductionBatch),
          ) as DeductionBatch;
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
  SetDeductionBatchStatus200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetDeductionBatchStatus200ResponseBuilder();
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

