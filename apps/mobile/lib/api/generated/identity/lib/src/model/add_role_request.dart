//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'add_role_request.g.dart';

/// AddRoleRequest
///
/// Properties:
/// * [phoneVerifiedToken] - A FRESH single-use phone-verified JWT from `POST /otp/verify` (a normal OTP round). The phone is read from this token (not the body) and the token is consumed; it re-proves ownership of the account's phone so a token-less pending account can add a second role. 
/// * [role] - The SECOND role to add. Must differ from the account's current role and any role it already holds (else 409 `ROLE_ALREADY_HELD`). `admin` is rejected (403). 
@BuiltValue()
abstract class AddRoleRequest implements Built<AddRoleRequest, AddRoleRequestBuilder> {
  /// A FRESH single-use phone-verified JWT from `POST /otp/verify` (a normal OTP round). The phone is read from this token (not the body) and the token is consumed; it re-proves ownership of the account's phone so a token-less pending account can add a second role. 
  @BuiltValueField(wireName: r'phone_verified_token')
  String get phoneVerifiedToken;

  /// The SECOND role to add. Must differ from the account's current role and any role it already holds (else 409 `ROLE_ALREADY_HELD`). `admin` is rejected (403). 
  @BuiltValueField(wireName: r'role')
  AddRoleRequestRoleEnum get role;
  // enum roleEnum {  guard,  customer,  };

  AddRoleRequest._();

  factory AddRoleRequest([void updates(AddRoleRequestBuilder b)]) = _$AddRoleRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AddRoleRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AddRoleRequest> get serializer => _$AddRoleRequestSerializer();
}

class _$AddRoleRequestSerializer implements PrimitiveSerializer<AddRoleRequest> {
  @override
  final Iterable<Type> types = const [AddRoleRequest, _$AddRoleRequest];

  @override
  final String wireName = r'AddRoleRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AddRoleRequest object, {
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
      specifiedType: const FullType(AddRoleRequestRoleEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AddRoleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AddRoleRequestBuilder result,
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
            specifiedType: const FullType(AddRoleRequestRoleEnum),
          ) as AddRoleRequestRoleEnum;
          result.role = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AddRoleRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AddRoleRequestBuilder();
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

class AddRoleRequestRoleEnum extends EnumClass {

  /// The SECOND role to add. Must differ from the account's current role and any role it already holds (else 409 `ROLE_ALREADY_HELD`). `admin` is rejected (403). 
  @BuiltValueEnumConst(wireName: r'guard')
  static const AddRoleRequestRoleEnum guard = _$addRoleRequestRoleEnum_guard;
  /// The SECOND role to add. Must differ from the account's current role and any role it already holds (else 409 `ROLE_ALREADY_HELD`). `admin` is rejected (403). 
  @BuiltValueEnumConst(wireName: r'customer')
  static const AddRoleRequestRoleEnum customer = _$addRoleRequestRoleEnum_customer;

  static Serializer<AddRoleRequestRoleEnum> get serializer => _$addRoleRequestRoleEnumSerializer;

  const AddRoleRequestRoleEnum._(String name): super(name);

  static BuiltSet<AddRoleRequestRoleEnum> get values => _$addRoleRequestRoleEnumValues;
  static AddRoleRequestRoleEnum valueOf(String name) => _$addRoleRequestRoleEnumValueOf(name);
}

