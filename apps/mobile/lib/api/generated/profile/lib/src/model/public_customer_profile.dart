//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'public_customer_profile.g.dart';

/// The lean, GUARD-facing customer mini-profile — the mirror of `PublicGuardProfile` for the other direction. NARROW by design: only the customer's name + photo (so the guard's job sheet can address them by name and show their face); NEVER the address/company/email/phone PII. `full_name` is reachable by any guard-role caller — from the job offer onwards, per the 2026-07-11 product decision (see `GET /customers/{id}/public`). `avatar_url` is a short-lived presigned GET URL (the raw S3 key is never on the wire), `null` when the customer has not set an avatar. 
///
/// Properties:
/// * [userId] 
/// * [fullName] 
/// * [avatarUrl] - Presigned GET URL for the customer's avatar (expires in ~1h), or null when unset.
@BuiltValue()
abstract class PublicCustomerProfile implements Built<PublicCustomerProfile, PublicCustomerProfileBuilder> {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  @BuiltValueField(wireName: r'full_name')
  String? get fullName;

  /// Presigned GET URL for the customer's avatar (expires in ~1h), or null when unset.
  @BuiltValueField(wireName: r'avatar_url')
  String? get avatarUrl;

  PublicCustomerProfile._();

  factory PublicCustomerProfile([void updates(PublicCustomerProfileBuilder b)]) = _$PublicCustomerProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PublicCustomerProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PublicCustomerProfile> get serializer => _$PublicCustomerProfileSerializer();
}

class _$PublicCustomerProfileSerializer implements PrimitiveSerializer<PublicCustomerProfile> {
  @override
  final Iterable<Type> types = const [PublicCustomerProfile, _$PublicCustomerProfile];

  @override
  final String wireName = r'PublicCustomerProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PublicCustomerProfile object, {
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
    PublicCustomerProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PublicCustomerProfileBuilder result,
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
  PublicCustomerProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PublicCustomerProfileBuilder();
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

