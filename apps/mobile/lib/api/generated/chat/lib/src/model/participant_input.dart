//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'participant_input.g.dart';

/// ParticipantInput
///
/// Properties:
/// * [userId] 
/// * [role] - This participant's role IN THIS conversation (drives alignment + receipts).
/// * [displayName] - Booking-derived display name (denormalized; no cross-schema JOIN at read).
/// * [avatarUrl] - Booking-derived avatar URL (denormalized).
@BuiltValue()
abstract class ParticipantInput implements Built<ParticipantInput, ParticipantInputBuilder> {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  /// This participant's role IN THIS conversation (drives alignment + receipts).
  @BuiltValueField(wireName: r'role')
  ParticipantInputRoleEnum get role;
  // enum roleEnum {  guard,  customer,  };

  /// Booking-derived display name (denormalized; no cross-schema JOIN at read).
  @BuiltValueField(wireName: r'display_name')
  String? get displayName;

  /// Booking-derived avatar URL (denormalized).
  @BuiltValueField(wireName: r'avatar_url')
  String? get avatarUrl;

  ParticipantInput._();

  factory ParticipantInput([void updates(ParticipantInputBuilder b)]) = _$ParticipantInput;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ParticipantInputBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ParticipantInput> get serializer => _$ParticipantInputSerializer();
}

class _$ParticipantInputSerializer implements PrimitiveSerializer<ParticipantInput> {
  @override
  final Iterable<Type> types = const [ParticipantInput, _$ParticipantInput];

  @override
  final String wireName = r'ParticipantInput';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ParticipantInput object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(ParticipantInputRoleEnum),
    );
    if (object.displayName != null) {
      yield r'display_name';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
    if (object.avatarUrl != null) {
      yield r'avatar_url';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ParticipantInput object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ParticipantInputBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ParticipantInputRoleEnum),
          ) as ParticipantInputRoleEnum;
          result.role = valueDes;
          break;
        case r'display_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'avatar_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ParticipantInput deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ParticipantInputBuilder();
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

class ParticipantInputRoleEnum extends EnumClass {

  /// This participant's role IN THIS conversation (drives alignment + receipts).
  @BuiltValueEnumConst(wireName: r'guard')
  static const ParticipantInputRoleEnum guard = _$participantInputRoleEnum_guard;
  /// This participant's role IN THIS conversation (drives alignment + receipts).
  @BuiltValueEnumConst(wireName: r'customer')
  static const ParticipantInputRoleEnum customer = _$participantInputRoleEnum_customer;

  static Serializer<ParticipantInputRoleEnum> get serializer => _$participantInputRoleEnumSerializer;

  const ParticipantInputRoleEnum._(String name): super(name);

  static BuiltSet<ParticipantInputRoleEnum> get values => _$participantInputRoleEnumValues;
  static ParticipantInputRoleEnum valueOf(String name) => _$participantInputRoleEnumValueOf(name);
}

