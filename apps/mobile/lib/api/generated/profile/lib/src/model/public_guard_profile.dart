//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'public_guard_profile.g.dart';

/// The lean, customer-facing guard mini-profile for the live-tracking map. NARROW by design — only what identifies the assigned guard (name + experience); NEVER bank/address/DOB/ emergency-contact PII. `full_name` is reachable by a non-owner ONLY under the active-booking IDOR gate (see `GET /guards/{id}/public`). Photo deferred (no avatar storage yet). 
///
/// Properties:
/// * [userId] 
/// * [fullName] 
/// * [yearsOfExperience] 
@BuiltValue()
abstract class PublicGuardProfile implements Built<PublicGuardProfile, PublicGuardProfileBuilder> {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  @BuiltValueField(wireName: r'full_name')
  String? get fullName;

  @BuiltValueField(wireName: r'years_of_experience')
  int? get yearsOfExperience;

  PublicGuardProfile._();

  factory PublicGuardProfile([void updates(PublicGuardProfileBuilder b)]) = _$PublicGuardProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PublicGuardProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PublicGuardProfile> get serializer => _$PublicGuardProfileSerializer();
}

class _$PublicGuardProfileSerializer implements PrimitiveSerializer<PublicGuardProfile> {
  @override
  final Iterable<Type> types = const [PublicGuardProfile, _$PublicGuardProfile];

  @override
  final String wireName = r'PublicGuardProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PublicGuardProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    if (object.fullName != null) {
      yield r'full_name';
      yield serializers.serialize(
        object.fullName,
        specifiedType: const FullType(String),
      );
    }
    if (object.yearsOfExperience != null) {
      yield r'years_of_experience';
      yield serializers.serialize(
        object.yearsOfExperience,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PublicGuardProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PublicGuardProfileBuilder result,
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
        case r'full_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fullName = valueDes;
          break;
        case r'years_of_experience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.yearsOfExperience = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PublicGuardProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PublicGuardProfileBuilder();
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

