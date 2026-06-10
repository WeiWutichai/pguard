//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_otp_api/src/model/verify_otp_result.dart';
import 'package:pguard_otp_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'verify_otp200_response.g.dart';

/// VerifyOtp200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class VerifyOtp200Response implements ApiResponseEnvelope, Built<VerifyOtp200Response, VerifyOtp200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  VerifyOtpResult? get data;

  VerifyOtp200Response._();

  factory VerifyOtp200Response([void updates(VerifyOtp200ResponseBuilder b)]) = _$VerifyOtp200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VerifyOtp200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VerifyOtp200Response> get serializer => _$VerifyOtp200ResponseSerializer();
}

class _$VerifyOtp200ResponseSerializer implements PrimitiveSerializer<VerifyOtp200Response> {
  @override
  final Iterable<Type> types = const [VerifyOtp200Response, _$VerifyOtp200Response];

  @override
  final String wireName = r'VerifyOtp200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VerifyOtp200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(VerifyOtpResult),
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
    VerifyOtp200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VerifyOtp200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(VerifyOtpResult),
          ) as VerifyOtpResult;
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
  VerifyOtp200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VerifyOtp200ResponseBuilder();
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

