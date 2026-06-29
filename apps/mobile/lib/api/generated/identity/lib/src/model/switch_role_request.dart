//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'switch_role_request.g.dart';

/// SwitchRoleRequest
///
/// Properties:
/// * [role] - The role to switch the active session into. MUST be one the caller is enrolled in (in `available_roles` / `GET /auth/me` `roles`) — otherwise `409 ROLE_NOT_ENROLLED`. 
@BuiltValue()
abstract class SwitchRoleRequest implements Built<SwitchRoleRequest, SwitchRoleRequestBuilder> {
  /// The role to switch the active session into. MUST be one the caller is enrolled in (in `available_roles` / `GET /auth/me` `roles`) — otherwise `409 ROLE_NOT_ENROLLED`. 
  @BuiltValueField(wireName: r'role')
  SwitchRoleRequestRoleEnum get role;
  // enum roleEnum {  guard,  customer,  };

  SwitchRoleRequest._();

  factory SwitchRoleRequest([void updates(SwitchRoleRequestBuilder b)]) = _$SwitchRoleRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SwitchRoleRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SwitchRoleRequest> get serializer => _$SwitchRoleRequestSerializer();
}

class _$SwitchRoleRequestSerializer implements PrimitiveSerializer<SwitchRoleRequest> {
  @override
  final Iterable<Type> types = const [SwitchRoleRequest, _$SwitchRoleRequest];

  @override
  final String wireName = r'SwitchRoleRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SwitchRoleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(SwitchRoleRequestRoleEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SwitchRoleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SwitchRoleRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SwitchRoleRequestRoleEnum),
          ) as SwitchRoleRequestRoleEnum;
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
  SwitchRoleRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SwitchRoleRequestBuilder();
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

class SwitchRoleRequestRoleEnum extends EnumClass {

  /// The role to switch the active session into. MUST be one the caller is enrolled in (in `available_roles` / `GET /auth/me` `roles`) — otherwise `409 ROLE_NOT_ENROLLED`. 
  @BuiltValueEnumConst(wireName: r'guard')
  static const SwitchRoleRequestRoleEnum guard = _$switchRoleRequestRoleEnum_guard;
  /// The role to switch the active session into. MUST be one the caller is enrolled in (in `available_roles` / `GET /auth/me` `roles`) — otherwise `409 ROLE_NOT_ENROLLED`. 
  @BuiltValueEnumConst(wireName: r'customer')
  static const SwitchRoleRequestRoleEnum customer = _$switchRoleRequestRoleEnum_customer;

  static Serializer<SwitchRoleRequestRoleEnum> get serializer => _$switchRoleRequestRoleEnumSerializer;

  const SwitchRoleRequestRoleEnum._(String name): super(name);

  static BuiltSet<SwitchRoleRequestRoleEnum> get values => _$switchRoleRequestRoleEnumValues;
  static SwitchRoleRequestRoleEnum valueOf(String name) => _$switchRoleRequestRoleEnumValueOf(name);
}

