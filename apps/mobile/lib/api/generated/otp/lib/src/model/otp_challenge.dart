//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'otp_challenge.g.dart';

/// OtpChallenge
///
/// Properties:
/// * [challengeId] - Opaque id binding the captcha answer in Redis
/// * [question] 
/// * [expiresIn] - Seconds until the captcha expires
@BuiltValue()
abstract class OtpChallenge implements Built<OtpChallenge, OtpChallengeBuilder> {
  /// Opaque id binding the captcha answer in Redis
  @BuiltValueField(wireName: r'challenge_id')
  String get challengeId;

  @BuiltValueField(wireName: r'question')
  String get question;

  /// Seconds until the captcha expires
  @BuiltValueField(wireName: r'expires_in')
  int get expiresIn;

  OtpChallenge._();

  factory OtpChallenge([void updates(OtpChallengeBuilder b)]) = _$OtpChallenge;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OtpChallengeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OtpChallenge> get serializer => _$OtpChallengeSerializer();
}

class _$OtpChallengeSerializer implements PrimitiveSerializer<OtpChallenge> {
  @override
  final Iterable<Type> types = const [OtpChallenge, _$OtpChallenge];

  @override
  final String wireName = r'OtpChallenge';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OtpChallenge object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'challenge_id';
    yield serializers.serialize(
      object.challengeId,
      specifiedType: const FullType(String),
    );
    yield r'question';
    yield serializers.serialize(
      object.question,
      specifiedType: const FullType(String),
    );
    yield r'expires_in';
    yield serializers.serialize(
      object.expiresIn,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OtpChallenge object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OtpChallengeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'challenge_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.challengeId = valueDes;
          break;
        case r'question':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.question = valueDes;
          break;
        case r'expires_in':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.expiresIn = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OtpChallenge deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OtpChallengeBuilder();
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

