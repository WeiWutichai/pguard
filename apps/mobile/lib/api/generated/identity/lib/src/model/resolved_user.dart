//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_identity_api/src/model/user_role.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'resolved_user.g.dart';

/// One resolved identity for the internal name-resolver — `{ role, display_name, phone }` and nothing else (least-privilege: still NEVER email, bank or address). `display_name` is `null` when none is set. 
///
/// Properties:
/// * [role] 
/// * [displayName] 
/// * [phone] - The account's LOGIN phone (`identity.users.phone`) — the number this person registered with and signs in with. It is the OTP login key, so every live account has exactly one and it is always populated; `null` would mean a malformed row.  DISTINCT from a customer profile's `contact_phone`, which is an OPTIONAL extra the customer may type into their profile (often blank, sometimes a third party's number). Consumers surfacing \"how do I reach this person\" want THIS field. Admin-surface PII — never log it or expose it outside an admin-authenticated view. 
@BuiltValue()
abstract class ResolvedUser implements Built<ResolvedUser, ResolvedUserBuilder> {
  @BuiltValueField(wireName: r'role')
  UserRole get role;
  // enum roleEnum {  admin,  customer,  guard,  };

  @BuiltValueField(wireName: r'display_name')
  String? get displayName;

  /// The account's LOGIN phone (`identity.users.phone`) — the number this person registered with and signs in with. It is the OTP login key, so every live account has exactly one and it is always populated; `null` would mean a malformed row.  DISTINCT from a customer profile's `contact_phone`, which is an OPTIONAL extra the customer may type into their profile (often blank, sometimes a third party's number). Consumers surfacing \"how do I reach this person\" want THIS field. Admin-surface PII — never log it or expose it outside an admin-authenticated view. 
  @BuiltValueField(wireName: r'phone')
  String? get phone;

  ResolvedUser._();

  factory ResolvedUser([void updates(ResolvedUserBuilder b)]) = _$ResolvedUser;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ResolvedUserBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ResolvedUser> get serializer => _$ResolvedUserSerializer();
}

class _$ResolvedUserSerializer implements PrimitiveSerializer<ResolvedUser> {
  @override
  final Iterable<Type> types = const [ResolvedUser, _$ResolvedUser];

  @override
  final String wireName = r'ResolvedUser';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ResolvedUser object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(UserRole),
    );
    if (object.displayName != null) {
      yield r'display_name';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
    if (object.phone != null) {
      yield r'phone';
      yield serializers.serialize(
        object.phone,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ResolvedUser object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ResolvedUserBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(UserRole),
          ) as UserRole;
          result.role = valueDes;
          break;
        case r'display_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phone = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ResolvedUser deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ResolvedUserBuilder();
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

