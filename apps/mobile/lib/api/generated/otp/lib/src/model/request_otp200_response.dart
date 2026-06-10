//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_otp_api/src/model/request_otp_result.dart';
import 'package:pguard_otp_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'request_otp200_response.g.dart';

/// RequestOtp200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class RequestOtp200Response implements ApiResponseEnvelope, Built<RequestOtp200Response, RequestOtp200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  RequestOtpResult? get data;

  RequestOtp200Response._();

  factory RequestOtp200Response([void updates(RequestOtp200ResponseBuilder b)]) = _$RequestOtp200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RequestOtp200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RequestOtp200Response> get serializer => _$RequestOtp200ResponseSerializer();
}

class _$RequestOtp200ResponseSerializer implements PrimitiveSerializer<RequestOtp200Response> {
  @override
  final Iterable<Type> types = const [RequestOtp200Response, _$RequestOtp200Response];

  @override
  final String wireName = r'RequestOtp200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RequestOtp200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(RequestOtpResult),
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
    RequestOtp200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RequestOtp200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RequestOtpResult),
          ) as RequestOtpResult;
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
  RequestOtp200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RequestOtp200ResponseBuilder();
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

