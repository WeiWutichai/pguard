//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_identity_api/src/model/token_pair.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_identity_api/src/model/two_factor_challenge.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'login200_response_all_of_data.g.dart';

/// Login200ResponseAllOfData
///
/// Properties:
/// * [accessToken] - Short-lived access JWT (HS256).
/// * [refreshToken] - Single-use rotating refresh token.
/// * [expiresIn] - Access-token lifetime
/// * [tokenType] 
/// * [twoFactorRequired] 
/// * [challengeToken] 
@BuiltValue()
abstract class Login200ResponseAllOfData implements Built<Login200ResponseAllOfData, Login200ResponseAllOfDataBuilder> {
  /// One Of [TokenPair], [TwoFactorChallenge]
  OneOf get oneOf;

  Login200ResponseAllOfData._();

  factory Login200ResponseAllOfData([void updates(Login200ResponseAllOfDataBuilder b)]) = _$Login200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(Login200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Login200ResponseAllOfData> get serializer => _$Login200ResponseAllOfDataSerializer();
}

class _$Login200ResponseAllOfDataSerializer implements PrimitiveSerializer<Login200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [Login200ResponseAllOfData, _$Login200ResponseAllOfData];

  @override
  final String wireName = r'Login200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Login200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
  }

  @override
  Object serialize(
    Serializers serializers,
    Login200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value, specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  Login200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = Login200ResponseAllOfDataBuilder();
    Object? oneOfDataSrc;
    final targetType = const FullType(OneOf, [FullType(TokenPair), FullType(TwoFactorChallenge), ]);
    oneOfDataSrc = serialized;
    result.oneOf = serializers.deserialize(oneOfDataSrc, specifiedType: targetType) as OneOf;
    return result.build();
  }
}

class Login200ResponseAllOfDataTokenTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'Bearer')
  static const Login200ResponseAllOfDataTokenTypeEnum bearer = _$login200ResponseAllOfDataTokenTypeEnum_bearer;

  static Serializer<Login200ResponseAllOfDataTokenTypeEnum> get serializer => _$login200ResponseAllOfDataTokenTypeEnumSerializer;

  const Login200ResponseAllOfDataTokenTypeEnum._(String name): super(name);

  static BuiltSet<Login200ResponseAllOfDataTokenTypeEnum> get values => _$login200ResponseAllOfDataTokenTypeEnumValues;
  static Login200ResponseAllOfDataTokenTypeEnum valueOf(String name) => _$login200ResponseAllOfDataTokenTypeEnumValueOf(name);
}

class Login200ResponseAllOfDataTwoFactorRequiredEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'true')
  static const Login200ResponseAllOfDataTwoFactorRequiredEnum true_ = _$login200ResponseAllOfDataTwoFactorRequiredEnum_true_;

  static Serializer<Login200ResponseAllOfDataTwoFactorRequiredEnum> get serializer => _$login200ResponseAllOfDataTwoFactorRequiredEnumSerializer;

  const Login200ResponseAllOfDataTwoFactorRequiredEnum._(String name): super(name);

  static BuiltSet<Login200ResponseAllOfDataTwoFactorRequiredEnum> get values => _$login200ResponseAllOfDataTwoFactorRequiredEnumValues;
  static Login200ResponseAllOfDataTwoFactorRequiredEnum valueOf(String name) => _$login200ResponseAllOfDataTwoFactorRequiredEnumValueOf(name);
}

