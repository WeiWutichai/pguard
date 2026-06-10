//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_otp_api/src/model/otp_challenge.dart';
import 'package:pguard_otp_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'otp_challenge200_response.g.dart';

/// OtpChallenge200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class OtpChallenge200Response implements ApiResponseEnvelope, Built<OtpChallenge200Response, OtpChallenge200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  OtpChallenge? get data;

  OtpChallenge200Response._();

  factory OtpChallenge200Response([void updates(OtpChallenge200ResponseBuilder b)]) = _$OtpChallenge200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OtpChallenge200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OtpChallenge200Response> get serializer => _$OtpChallenge200ResponseSerializer();
}

class _$OtpChallenge200ResponseSerializer implements PrimitiveSerializer<OtpChallenge200Response> {
  @override
  final Iterable<Type> types = const [OtpChallenge200Response, _$OtpChallenge200Response];

  @override
  final String wireName = r'OtpChallenge200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OtpChallenge200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(OtpChallenge),
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
    OtpChallenge200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OtpChallenge200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(OtpChallenge),
          ) as OtpChallenge;
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
  OtpChallenge200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OtpChallenge200ResponseBuilder();
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

