//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'resolved_name.g.dart';

/// One resolved identity for the admin name-resolver: a display name (admin-only PII here) + the role it was resolved as. NEVER any other PII. `display_name` is `null` when the row exists but has no name yet (mid-onboarding) — the role is still authoritative.  `role` is `guard` / `customer` (from profile's own tables) OR `admin`: profile merges ADMIN names from identity's service-JWT'd `POST /internal/users/names` (admins have no profile row here — their name lives only in identity). An id with no row in EITHER place (genuinely unknown / deleted) is still OMITTED from the response map; the client uses a role-label fallback for it. 
///
/// Properties:
/// * [role] - The role this id was resolved as — `guard` / `customer` from profile's tables, or `admin` merged from identity. 
/// * [displayName] - The user's full name, or null if not set yet.
@BuiltValue()
abstract class ResolvedName implements Built<ResolvedName, ResolvedNameBuilder> {
  /// The role this id was resolved as — `guard` / `customer` from profile's tables, or `admin` merged from identity. 
  @BuiltValueField(wireName: r'role')
  ResolvedNameRoleEnum get role;
  // enum roleEnum {  guard,  customer,  admin,  };

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

  /// The role this id was resolved as — `guard` / `customer` from profile's tables, or `admin` merged from identity. 
  @BuiltValueEnumConst(wireName: r'guard')
  static const ResolvedNameRoleEnum guard = _$resolvedNameRoleEnum_guard;
  /// The role this id was resolved as — `guard` / `customer` from profile's tables, or `admin` merged from identity. 
  @BuiltValueEnumConst(wireName: r'customer')
  static const ResolvedNameRoleEnum customer = _$resolvedNameRoleEnum_customer;
  /// The role this id was resolved as — `guard` / `customer` from profile's tables, or `admin` merged from identity. 
  @BuiltValueEnumConst(wireName: r'admin')
  static const ResolvedNameRoleEnum admin = _$resolvedNameRoleEnum_admin;

  static Serializer<ResolvedNameRoleEnum> get serializer => _$resolvedNameRoleEnumSerializer;

  const ResolvedNameRoleEnum._(String name): super(name);

  static BuiltSet<ResolvedNameRoleEnum> get values => _$resolvedNameRoleEnumValues;
  static ResolvedNameRoleEnum valueOf(String name) => _$resolvedNameRoleEnumValueOf(name);
}

