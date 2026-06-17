//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/public_guard_profile.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_public_guard_profile200_response.g.dart';

/// GetPublicGuardProfile200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetPublicGuardProfile200Response implements ApiResponseEnvelope, Built<GetPublicGuardProfile200Response, GetPublicGuardProfile200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  PublicGuardProfile? get data;

  GetPublicGuardProfile200Response._();

  factory GetPublicGuardProfile200Response([void updates(GetPublicGuardProfile200ResponseBuilder b)]) = _$GetPublicGuardProfile200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetPublicGuardProfile200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetPublicGuardProfile200Response> get serializer => _$GetPublicGuardProfile200ResponseSerializer();
}

class _$GetPublicGuardProfile200ResponseSerializer implements PrimitiveSerializer<GetPublicGuardProfile200Response> {
  @override
  final Iterable<Type> types = const [GetPublicGuardProfile200Response, _$GetPublicGuardProfile200Response];

  @override
  final String wireName = r'GetPublicGuardProfile200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetPublicGuardProfile200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(PublicGuardProfile),
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
    GetPublicGuardProfile200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetPublicGuardProfile200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PublicGuardProfile),
          ) as PublicGuardProfile;
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
  GetPublicGuardProfile200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetPublicGuardProfile200ResponseBuilder();
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

