//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/my_profile.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_my_profile200_response.g.dart';

/// GetMyProfile200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetMyProfile200Response implements ApiResponseEnvelope, Built<GetMyProfile200Response, GetMyProfile200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  MyProfile? get data;

  GetMyProfile200Response._();

  factory GetMyProfile200Response([void updates(GetMyProfile200ResponseBuilder b)]) = _$GetMyProfile200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetMyProfile200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetMyProfile200Response> get serializer => _$GetMyProfile200ResponseSerializer();
}

class _$GetMyProfile200ResponseSerializer implements PrimitiveSerializer<GetMyProfile200Response> {
  @override
  final Iterable<Type> types = const [GetMyProfile200Response, _$GetMyProfile200Response];

  @override
  final String wireName = r'GetMyProfile200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetMyProfile200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(MyProfile),
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
    GetMyProfile200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetMyProfile200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MyProfile),
          ) as MyProfile;
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
  GetMyProfile200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetMyProfile200ResponseBuilder();
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

