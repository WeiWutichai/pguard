//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'two_factor_challenge.g.dart';

/// Login outcome when 2FA is enabled — NO tokens. The client posts `challenge_token` to `POST /auth/2fa/verify` with a code to complete login. 
///
/// Properties:
/// * [twoFactorRequired] 
/// * [challengeToken] 
@BuiltValue()
abstract class TwoFactorChallenge implements Built<TwoFactorChallenge, TwoFactorChallengeBuilder> {
  @BuiltValueField(wireName: r'two_factor_required')
  TwoFactorChallengeTwoFactorRequiredEnum get twoFactorRequired;
  // enum twoFactorRequiredEnum {  true,  };

  @BuiltValueField(wireName: r'challenge_token')
  String get challengeToken;

  TwoFactorChallenge._();

  factory TwoFactorChallenge([void updates(TwoFactorChallengeBuilder b)]) = _$TwoFactorChallenge;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TwoFactorChallengeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TwoFactorChallenge> get serializer => _$TwoFactorChallengeSerializer();
}

class _$TwoFactorChallengeSerializer implements PrimitiveSerializer<TwoFactorChallenge> {
  @override
  final Iterable<Type> types = const [TwoFactorChallenge, _$TwoFactorChallenge];

  @override
  final String wireName = r'TwoFactorChallenge';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TwoFactorChallenge object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'two_factor_required';
    yield serializers.serialize(
      object.twoFactorRequired,
      specifiedType: const FullType(TwoFactorChallengeTwoFactorRequiredEnum),
    );
    yield r'challenge_token';
    yield serializers.serialize(
      object.challengeToken,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TwoFactorChallenge object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TwoFactorChallengeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'two_factor_required':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(TwoFactorChallengeTwoFactorRequiredEnum),
          ) as TwoFactorChallengeTwoFactorRequiredEnum;
          result.twoFactorRequired = valueDes;
          break;
        case r'challenge_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.challengeToken = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TwoFactorChallenge deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TwoFactorChallengeBuilder();
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

class TwoFactorChallengeTwoFactorRequiredEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'true')
  static const TwoFactorChallengeTwoFactorRequiredEnum true_ = _$twoFactorChallengeTwoFactorRequiredEnum_true_;

  static Serializer<TwoFactorChallengeTwoFactorRequiredEnum> get serializer => _$twoFactorChallengeTwoFactorRequiredEnumSerializer;

  const TwoFactorChallengeTwoFactorRequiredEnum._(String name): super(name);

  static BuiltSet<TwoFactorChallengeTwoFactorRequiredEnum> get values => _$twoFactorChallengeTwoFactorRequiredEnumValues;
  static TwoFactorChallengeTwoFactorRequiredEnum valueOf(String name) => _$twoFactorChallengeTwoFactorRequiredEnumValueOf(name);
}

