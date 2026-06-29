//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_identity_api/src/model/user_role.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_token_pair.g.dart';

/// The `data` of a successful no-2FA login (multi-role, Option A): the usual `TokenPair` fields PLUS `available_roles`. BACKWARD COMPATIBLE — a single-role user sees every `TokenPair` field unchanged plus `available_roles: [their_role]`; the access token is minted with the registration/primary role exactly as before. 
///
/// Properties:
/// * [accessToken] - Short-lived access JWT (HS256).
/// * [refreshToken] - Single-use rotating refresh token.
/// * [expiresIn] - Access-token lifetime
/// * [tokenType] 
/// * [availableRoles] - The account's APPROVED roles (`user_roles`). `[role]` for a single-role user; both for a dual-role user (the app can then offer `POST /auth/switch-role`). 
@BuiltValue()
abstract class LoginTokenPair implements Built<LoginTokenPair, LoginTokenPairBuilder> {
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
  LoginTokenPairTokenTypeEnum get tokenType;
  // enum tokenTypeEnum {  Bearer,  };

  /// The account's APPROVED roles (`user_roles`). `[role]` for a single-role user; both for a dual-role user (the app can then offer `POST /auth/switch-role`). 
  @BuiltValueField(wireName: r'available_roles')
  BuiltList<UserRole>? get availableRoles;

  LoginTokenPair._();

  factory LoginTokenPair([void updates(LoginTokenPairBuilder b)]) = _$LoginTokenPair;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginTokenPairBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginTokenPair> get serializer => _$LoginTokenPairSerializer();
}

class _$LoginTokenPairSerializer implements PrimitiveSerializer<LoginTokenPair> {
  @override
  final Iterable<Type> types = const [LoginTokenPair, _$LoginTokenPair];

  @override
  final String wireName = r'LoginTokenPair';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginTokenPair object, {
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
      specifiedType: const FullType(LoginTokenPairTokenTypeEnum),
    );
    if (object.availableRoles != null) {
      yield r'available_roles';
      yield serializers.serialize(
        object.availableRoles,
        specifiedType: const FullType(BuiltList, [FullType(UserRole)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginTokenPair object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginTokenPairBuilder result,
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
            specifiedType: const FullType(LoginTokenPairTokenTypeEnum),
          ) as LoginTokenPairTokenTypeEnum;
          result.tokenType = valueDes;
          break;
        case r'available_roles':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(UserRole)]),
          ) as BuiltList<UserRole>;
          result.availableRoles.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginTokenPair deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginTokenPairBuilder();
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

class LoginTokenPairTokenTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'Bearer')
  static const LoginTokenPairTokenTypeEnum bearer = _$loginTokenPairTokenTypeEnum_bearer;

  static Serializer<LoginTokenPairTokenTypeEnum> get serializer => _$loginTokenPairTokenTypeEnumSerializer;

  const LoginTokenPairTokenTypeEnum._(String name): super(name);

  static BuiltSet<LoginTokenPairTokenTypeEnum> get values => _$loginTokenPairTokenTypeEnumValues;
  static LoginTokenPairTokenTypeEnum valueOf(String name) => _$loginTokenPairTokenTypeEnumValueOf(name);
}

