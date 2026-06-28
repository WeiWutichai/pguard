//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_me_request.g.dart';

/// UpdateMeRequest
///
/// Properties:
/// * [displayName] - New display name (trimmed; 1–120 characters).
/// * [email] - New email — optional (omit / null / \"\" clears it). Lowercased + shape-checked server-side; UNIQUE across users (a collision → 409 `EMAIL_TAKEN`). 
@BuiltValue()
abstract class UpdateMeRequest implements Built<UpdateMeRequest, UpdateMeRequestBuilder> {
  /// New display name (trimmed; 1–120 characters).
  @BuiltValueField(wireName: r'display_name')
  String get displayName;

  /// New email — optional (omit / null / \"\" clears it). Lowercased + shape-checked server-side; UNIQUE across users (a collision → 409 `EMAIL_TAKEN`). 
  @BuiltValueField(wireName: r'email')
  String? get email;

  UpdateMeRequest._();

  factory UpdateMeRequest([void updates(UpdateMeRequestBuilder b)]) = _$UpdateMeRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateMeRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateMeRequest> get serializer => _$UpdateMeRequestSerializer();
}

class _$UpdateMeRequestSerializer implements PrimitiveSerializer<UpdateMeRequest> {
  @override
  final Iterable<Type> types = const [UpdateMeRequest, _$UpdateMeRequest];

  @override
  final String wireName = r'UpdateMeRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateMeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'display_name';
    yield serializers.serialize(
      object.displayName,
      specifiedType: const FullType(String),
    );
    if (object.email != null) {
      yield r'email';
      yield serializers.serialize(
        object.email,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateMeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpdateMeRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'display_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'email':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.email = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateMeRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateMeRequestBuilder();
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

