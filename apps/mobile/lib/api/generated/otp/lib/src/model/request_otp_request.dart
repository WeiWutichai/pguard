//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'request_otp_request.g.dart';

/// RequestOtpRequest
///
/// Properties:
/// * [phone] - Thai phone — 10 digits starting with 0
/// * [challengeId] - From GET /otp/challenge
/// * [answer] - The captcha answer (numeric string)
@BuiltValue()
abstract class RequestOtpRequest implements Built<RequestOtpRequest, RequestOtpRequestBuilder> {
  /// Thai phone — 10 digits starting with 0
  @BuiltValueField(wireName: r'phone')
  String get phone;

  /// From GET /otp/challenge
  @BuiltValueField(wireName: r'challenge_id')
  String get challengeId;

  /// The captcha answer (numeric string)
  @BuiltValueField(wireName: r'answer')
  String get answer;

  RequestOtpRequest._();

  factory RequestOtpRequest([void updates(RequestOtpRequestBuilder b)]) = _$RequestOtpRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RequestOtpRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RequestOtpRequest> get serializer => _$RequestOtpRequestSerializer();
}

class _$RequestOtpRequestSerializer implements PrimitiveSerializer<RequestOtpRequest> {
  @override
  final Iterable<Type> types = const [RequestOtpRequest, _$RequestOtpRequest];

  @override
  final String wireName = r'RequestOtpRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RequestOtpRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone';
    yield serializers.serialize(
      object.phone,
      specifiedType: const FullType(String),
    );
    yield r'challenge_id';
    yield serializers.serialize(
      object.challengeId,
      specifiedType: const FullType(String),
    );
    yield r'answer';
    yield serializers.serialize(
      object.answer,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RequestOtpRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RequestOtpRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phone = valueDes;
          break;
        case r'challenge_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.challengeId = valueDes;
          break;
        case r'answer':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.answer = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RequestOtpRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RequestOtpRequestBuilder();
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

