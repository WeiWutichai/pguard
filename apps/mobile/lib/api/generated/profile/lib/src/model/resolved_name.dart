//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'resolved_name.g.dart';

/// One resolved identity for the admin name-resolver: a display name (admin-only PII here) + the role it was resolved as. NEVER any other PII. `display_name` is `null` when the profile row exists but has no name yet (mid-onboarding) — the role is still authoritative. `role` is always `guard` or `customer`; `admin` is NEVER produced (admins have no profile row / stored name, so an admin id is OMITTED from the response map and the client uses a role-label fallback). 
///
/// Properties:
/// * [role] - The role this id was resolved as (derived from which profile table it is in).
/// * [displayName] - The user's full name, or null if not set yet.
@BuiltValue()
abstract class ResolvedName implements Built<ResolvedName, ResolvedNameBuilder> {
  /// The role this id was resolved as (derived from which profile table it is in).
  @BuiltValueField(wireName: r'role')
  ResolvedNameRoleEnum get role;
  // enum roleEnum {  guard,  customer,  };

  /// The user's full name, or null if not set yet.
  @BuiltValueField(wireName: r'display_name')
  String? get displayName;

  ResolvedName._();

  factory ResolvedName([void updates(ResolvedNameBuilder b)]) = _$ResolvedName;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ResolvedNameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ResolvedName> get serializer => _$ResolvedNameSerializer();
}

class _$ResolvedNameSerializer implements PrimitiveSerializer<ResolvedName> {
  @override
  final Iterable<Type> types = const [ResolvedName, _$ResolvedName];

  @override
  final String wireName = r'ResolvedName';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ResolvedName object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(ResolvedNameRoleEnum),
    );
    if (object.displayName != null) {
      yield r'display_name';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ResolvedName object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ResolvedNameBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ResolvedNameRoleEnum),
          ) as ResolvedNameRoleEnum;
          result.role = valueDes;
          break;
        case r'display_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ResolvedName deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ResolvedNameBuilder();
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

class ResolvedNameRoleEnum extends EnumClass {

  /// The role this id was resolved as (derived from which profile table it is in).
  @BuiltValueEnumConst(wireName: r'guard')
  static const ResolvedNameRoleEnum guard = _$resolvedNameRoleEnum_guard;
  /// The role this id was resolved as (derived from which profile table it is in).
  @BuiltValueEnumConst(wireName: r'customer')
  static const ResolvedNameRoleEnum customer = _$resolvedNameRoleEnum_customer;

  static Serializer<ResolvedNameRoleEnum> get serializer => _$resolvedNameRoleEnumSerializer;

  const ResolvedNameRoleEnum._(String name): super(name);

  static BuiltSet<ResolvedNameRoleEnum> get values => _$resolvedNameRoleEnumValues;
  static ResolvedNameRoleEnum valueOf(String name) => _$resolvedNameRoleEnumValueOf(name);
}

