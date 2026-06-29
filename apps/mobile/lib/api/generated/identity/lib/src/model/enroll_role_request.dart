//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enroll_role_request.g.dart';

/// EnrollRoleRequest
///
/// Properties:
/// * [role] - The NEW role to enroll (must NOT already be held). Returns a `profile_token` for that role's profile submission; the role is granted only after admin approval. 
@BuiltValue()
abstract class EnrollRoleRequest implements Built<EnrollRoleRequest, EnrollRoleRequestBuilder> {
  /// The NEW role to enroll (must NOT already be held). Returns a `profile_token` for that role's profile submission; the role is granted only after admin approval. 
  @BuiltValueField(wireName: r'role')
  EnrollRoleRequestRoleEnum get role;
  // enum roleEnum {  guard,  customer,  };

  EnrollRoleRequest._();

  factory EnrollRoleRequest([void updates(EnrollRoleRequestBuilder b)]) = _$EnrollRoleRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrollRoleRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrollRoleRequest> get serializer => _$EnrollRoleRequestSerializer();
}

class _$EnrollRoleRequestSerializer implements PrimitiveSerializer<EnrollRoleRequest> {
  @override
  final Iterable<Type> types = const [EnrollRoleRequest, _$EnrollRoleRequest];

  @override
  final String wireName = r'EnrollRoleRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrollRoleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(EnrollRoleRequestRoleEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrollRoleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrollRoleRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EnrollRoleRequestRoleEnum),
          ) as EnrollRoleRequestRoleEnum;
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
  EnrollRoleRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrollRoleRequestBuilder();
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

class EnrollRoleRequestRoleEnum extends EnumClass {

  /// The NEW role to enroll (must NOT already be held). Returns a `profile_token` for that role's profile submission; the role is granted only after admin approval. 
  @BuiltValueEnumConst(wireName: r'guard')
  static const EnrollRoleRequestRoleEnum guard = _$enrollRoleRequestRoleEnum_guard;
  /// The NEW role to enroll (must NOT already be held). Returns a `profile_token` for that role's profile submission; the role is granted only after admin approval. 
  @BuiltValueEnumConst(wireName: r'customer')
  static const EnrollRoleRequestRoleEnum customer = _$enrollRoleRequestRoleEnum_customer;

  static Serializer<EnrollRoleRequestRoleEnum> get serializer => _$enrollRoleRequestRoleEnumSerializer;

  const EnrollRoleRequestRoleEnum._(String name): super(name);

  static BuiltSet<EnrollRoleRequestRoleEnum> get values => _$enrollRoleRequestRoleEnumValues;
  static EnrollRoleRequestRoleEnum valueOf(String name) => _$enrollRoleRequestRoleEnumValueOf(name);
}

