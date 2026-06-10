//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'token_pair.g.dart';

/// TokenPair
///
/// Properties:
/// * [accessToken] - Short-lived access JWT (HS256).
/// * [refreshToken] - Single-use rotating refresh token.
/// * [expiresIn] - Access-token lifetime
/// * [tokenType] 
@BuiltValue()
abstract class TokenPair implements Built<TokenPair, TokenPairBuilder> {
  /// Short-lived access JWT (HS256).
  @BuiltValueField(wireName: r'access_token')
  String get accessToken;

  /// Single-use rotating refresh token.
  @BuiltValueField(wireName: r'refresh_token')
  String get refreshToken;

  /// Access-token lifetime
  @BuiltValueField(wireName: r'expires_in')
  int get expiresIn;

  @BuiltValueField(wireName: r'token_type')
  TokenPairTokenTypeEnum get tokenType;
  // enum tokenTypeEnum {  Bearer,  };

  TokenPair._();

  factory TokenPair([void updates(TokenPairBuilder b)]) = _$TokenPair;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TokenPairBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TokenPair> get serializer => _$TokenPairSerializer();
}

class _$TokenPairSerializer implements PrimitiveSerializer<TokenPair> {
  @override
  final Iterable<Type> types = const [TokenPair, _$TokenPair];

  @override
  final String wireName = r'TokenPair';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TokenPair object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'access_token';
    yield serializers.serialize(
      object.accessToken,
      specifiedType: const FullType(String),
    );
    yield r'refresh_token';
    yield serializers.serialize(
      object.refreshToken,
      specifiedType: const FullType(String),
    );
    yield r'expires_in';
    yield serializers.serialize(
      object.expiresIn,
      specifiedType: const FullType(int),
    );
    yield r'token_type';
    yield serializers.serialize(
      object.tokenType,
      specifiedType: const FullType(TokenPairTokenTypeEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TokenPair object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TokenPairBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'access_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.accessToken = valueDes;
          break;
        case r'refresh_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.refreshToken = valueDes;
          break;
        case r'expires_in':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.expiresIn = valueDes;
          break;
        case r'token_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(TokenPairTokenTypeEnum),
          ) as TokenPairTokenTypeEnum;
          result.tokenType = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TokenPair deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TokenPairBuilder();
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

class TokenPairTokenTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'Bearer')
  static const TokenPairTokenTypeEnum bearer = _$tokenPairTokenTypeEnum_bearer;

  static Serializer<TokenPairTokenTypeEnum> get serializer => _$tokenPairTokenTypeEnumSerializer;

  const TokenPairTokenTypeEnum._(String name): super(name);

  static BuiltSet<TokenPairTokenTypeEnum> get values => _$tokenPairTokenTypeEnumValues;
  static TokenPairTokenTypeEnum valueOf(String name) => _$tokenPairTokenTypeEnumValueOf(name);
}

