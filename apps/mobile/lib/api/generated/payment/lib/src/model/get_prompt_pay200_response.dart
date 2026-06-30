//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/prompt_pay_info.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_prompt_pay200_response.g.dart';

/// GetPromptPay200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetPromptPay200Response implements ApiResponseEnvelope, Built<GetPromptPay200Response, GetPromptPay200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  PromptPayInfo? get data;

  GetPromptPay200Response._();

  factory GetPromptPay200Response([void updates(GetPromptPay200ResponseBuilder b)]) = _$GetPromptPay200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetPromptPay200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetPromptPay200Response> get serializer => _$GetPromptPay200ResponseSerializer();
}

class _$GetPromptPay200ResponseSerializer implements PrimitiveSerializer<GetPromptPay200Response> {
  @override
  final Iterable<Type> types = const [GetPromptPay200Response, _$GetPromptPay200Response];

  @override
  final String wireName = r'GetPromptPay200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetPromptPay200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(PromptPayInfo),
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
    GetPromptPay200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetPromptPay200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PromptPayInfo),
          ) as PromptPayInfo;
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
  GetPromptPay200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetPromptPay200ResponseBuilder();
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

