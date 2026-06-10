//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'register_request.g.dart';

/// RegisterRequest
///
/// Properties:
/// * [phoneVerifiedToken] - The single-use phone-verified JWT from `POST /otp/verify`. The phone is read from this token (not the body) and the token is consumed (single-use). 
/// * [role] - Chosen at registration. `admin` is rejected (403 — no self-assignment).
/// * [pinHash] - Client-side SHA-256 hex of the user's PIN (64 hex chars); Argon2'd server-side.
@BuiltValue()
abstract class RegisterRequest implements Built<RegisterRequest, RegisterRequestBuilder> {
  /// The single-use phone-verified JWT from `POST /otp/verify`. The phone is read from this token (not the body) and the token is consumed (single-use). 
  @BuiltValueField(wireName: r'phone_verified_token')
  String get phoneVerifiedToken;

  /// Chosen at registration. `admin` is rejected (403 — no self-assignment).
  @BuiltValueField(wireName: r'role')
  RegisterRequestRoleEnum get role;
  // enum roleEnum {  guard,  customer,  };

  /// Client-side SHA-256 hex of the user's PIN (64 hex chars); Argon2'd server-side.
  @BuiltValueField(wireName: r'pin_hash')
  String get pinHash;

  RegisterRequest._();

  factory RegisterRequest([void updates(RegisterRequestBuilder b)]) = _$RegisterRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RegisterRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RegisterRequest> get serializer => _$RegisterRequestSerializer();
}

class _$RegisterRequestSerializer implements PrimitiveSerializer<RegisterRequest> {
  @override
  final Iterable<Type> types = const [RegisterRequest, _$RegisterRequest];

  @override
  final String wireName = r'RegisterRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RegisterRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone_verified_token';
    yield serializers.serialize(
      object.phoneVerifiedToken,
      specifiedType: const FullType(String),
    );
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(RegisterRequestRoleEnum),
    );
    yield r'pin_hash';
    yield serializers.serialize(
      object.pinHash,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RegisterRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RegisterRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'phone_verified_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phoneVerifiedToken = valueDes;
          break;
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RegisterRequestRoleEnum),
          ) as RegisterRequestRoleEnum;
          result.role = valueDes;
          break;
        case r'pin_hash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pinHash = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RegisterRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RegisterRequestBuilder();
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

class RegisterRequestRoleEnum extends EnumClass {

  /// Chosen at registration. `admin` is rejected (403 — no self-assignment).
  @BuiltValueEnumConst(wireName: r'guard')
  static const RegisterRequestRoleEnum guard = _$registerRequestRoleEnum_guard;
  /// Chosen at registration. `admin` is rejected (403 — no self-assignment).
  @BuiltValueEnumConst(wireName: r'customer')
  static const RegisterRequestRoleEnum customer = _$registerRequestRoleEnum_customer;

  static Serializer<RegisterRequestRoleEnum> get serializer => _$registerRequestRoleEnumSerializer;

  const RegisterRequestRoleEnum._(String name): super(name);

  static BuiltSet<RegisterRequestRoleEnum> get values => _$registerRequestRoleEnumValues;
  static RegisterRequestRoleEnum valueOf(String name) => _$registerRequestRoleEnumValueOf(name);
}

