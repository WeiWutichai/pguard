//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'customer_avatar_response.g.dart';

/// The result of a customer avatar upload/read: a short-lived (1h) presigned GET URL for the stored profile picture. The MIRROR of `GuardAvatarResponse`. The raw S3 key is NEVER exposed. 
///
/// Properties:
/// * [avatarUrl] - Presigned GET URL (expires in ~1h).
@BuiltValue()
abstract class CustomerAvatarResponse implements Built<CustomerAvatarResponse, CustomerAvatarResponseBuilder> {
  /// Presigned GET URL (expires in ~1h).
  @BuiltValueField(wireName: r'avatar_url')
  String get avatarUrl;

  CustomerAvatarResponse._();

  factory CustomerAvatarResponse([void updates(CustomerAvatarResponseBuilder b)]) = _$CustomerAvatarResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CustomerAvatarResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CustomerAvatarResponse> get serializer => _$CustomerAvatarResponseSerializer();
}

class _$CustomerAvatarResponseSerializer implements PrimitiveSerializer<CustomerAvatarResponse> {
  @override
  final Iterable<Type> types = const [CustomerAvatarResponse, _$CustomerAvatarResponse];

  @override
  final String wireName = r'CustomerAvatarResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CustomerAvatarResponse object, {
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
    CustomerAvatarResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CustomerAvatarResponseBuilder result,
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
  CustomerAvatarResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CustomerAvatarResponseBuilder();
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

