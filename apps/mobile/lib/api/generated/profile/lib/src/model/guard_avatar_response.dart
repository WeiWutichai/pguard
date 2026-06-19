//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_avatar_response.g.dart';

/// The result of a guard avatar upload/read: a short-lived (1h) presigned GET URL for the stored profile picture. The raw S3 key is NEVER exposed. 
///
/// Properties:
/// * [avatarUrl] - Presigned GET URL (expires in ~1h).
@BuiltValue()
abstract class GuardAvatarResponse implements Built<GuardAvatarResponse, GuardAvatarResponseBuilder> {
  /// Presigned GET URL (expires in ~1h).
  @BuiltValueField(wireName: r'avatar_url')
  String get avatarUrl;

  GuardAvatarResponse._();

  factory GuardAvatarResponse([void updates(GuardAvatarResponseBuilder b)]) = _$GuardAvatarResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuardAvatarResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardAvatarResponse> get serializer => _$GuardAvatarResponseSerializer();
}

class _$GuardAvatarResponseSerializer implements PrimitiveSerializer<GuardAvatarResponse> {
  @override
  final Iterable<Type> types = const [GuardAvatarResponse, _$GuardAvatarResponse];

  @override
  final String wireName = r'GuardAvatarResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardAvatarResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'avatar_url';
    yield serializers.serialize(
      object.avatarUrl,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuardAvatarResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardAvatarResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  GuardAvatarResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuardAvatarResponseBuilder();
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

