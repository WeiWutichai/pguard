//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'request_otp_request.g.dart';

/// RequestOtpRequest
///
/// Properties:
/// * [phone] - Thai phone — 10 digits starting with 0
/// * [challengeId] - From GET /otp/challenge
/// * [answer] - The captcha answer (numeric string)
/// * [purpose] - Which flow this code is for — BOUND here, stored with the code, and named in the SMS wording. Omitted → `phone_verify` (registration). `pin_reset` → forgot-PIN reset; `/otp/verify` will only mint a `pin_reset` token from a code requested this way.
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

  /// Which flow this code is for — BOUND here, stored with the code, and named in the SMS wording. Omitted → `phone_verify` (registration). `pin_reset` → forgot-PIN reset; `/otp/verify` will only mint a `pin_reset` token from a code requested this way.
  @BuiltValueField(wireName: r'purpose')
  RequestOtpRequestPurposeEnum? get purpose;
  // enum purposeEnum {  phone_verify,  pin_reset,  };

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
    if (object.purpose != null) {
      yield r'purpose';
      yield serializers.serialize(
        object.purpose,
        specifiedType: const FullType(RequestOtpRequestPurposeEnum),
      );
    }
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
        case r'purpose':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RequestOtpRequestPurposeEnum),
          ) as RequestOtpRequestPurposeEnum;
          result.purpose = valueDes;
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

class RequestOtpRequestPurposeEnum extends EnumClass {

  /// Which flow this code is for — BOUND here, stored with the code, and named in the SMS wording. Omitted → `phone_verify` (registration). `pin_reset` → forgot-PIN reset; `/otp/verify` will only mint a `pin_reset` token from a code requested this way.
  @BuiltValueEnumConst(wireName: r'phone_verify')
  static const RequestOtpRequestPurposeEnum phoneVerify = _$requestOtpRequestPurposeEnum_phoneVerify;
  /// Which flow this code is for — BOUND here, stored with the code, and named in the SMS wording. Omitted → `phone_verify` (registration). `pin_reset` → forgot-PIN reset; `/otp/verify` will only mint a `pin_reset` token from a code requested this way.
  @BuiltValueEnumConst(wireName: r'pin_reset')
  static const RequestOtpRequestPurposeEnum pinReset = _$requestOtpRequestPurposeEnum_pinReset;

  static Serializer<RequestOtpRequestPurposeEnum> get serializer => _$requestOtpRequestPurposeEnumSerializer;

  const RequestOtpRequestPurposeEnum._(String name): super(name);

  static BuiltSet<RequestOtpRequestPurposeEnum> get values => _$requestOtpRequestPurposeEnumValues;
  static RequestOtpRequestPurposeEnum valueOf(String name) => _$requestOtpRequestPurposeEnumValueOf(name);
}

