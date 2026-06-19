//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/guard_avatar_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_guard_avatar200_response.g.dart';

/// GetGuardAvatar200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetGuardAvatar200Response implements ApiResponseEnvelope, Built<GetGuardAvatar200Response, GetGuardAvatar200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  GuardAvatarResponse? get data;

  GetGuardAvatar200Response._();

  factory GetGuardAvatar200Response([void updates(GetGuardAvatar200ResponseBuilder b)]) = _$GetGuardAvatar200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetGuardAvatar200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetGuardAvatar200Response> get serializer => _$GetGuardAvatar200ResponseSerializer();
}

class _$GetGuardAvatar200ResponseSerializer implements PrimitiveSerializer<GetGuardAvatar200Response> {
  @override
  final Iterable<Type> types = const [GetGuardAvatar200Response, _$GetGuardAvatar200Response];

  @override
  final String wireName = r'GetGuardAvatar200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetGuardAvatar200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(GuardAvatarResponse),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
    yield r'success';
    yield serializers.serialize(
      object.success,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GetGuardAvatar200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetGuardAvatar200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(GuardAvatarResponse),
          ) as GuardAvatarResponse;
          result.data.replace(valueDes);
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GetGuardAvatar200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetGuardAvatar200ResponseBuilder();
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

