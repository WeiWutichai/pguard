//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_rating_api/src/model/api_response_envelope.dart';
import 'package:pguard_rating_api/src/model/guard_ratings.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_guard_ratings200_response.g.dart';

/// GetGuardRatings200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetGuardRatings200Response implements ApiResponseEnvelope, Built<GetGuardRatings200Response, GetGuardRatings200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  GuardRatings? get data;

  GetGuardRatings200Response._();

  factory GetGuardRatings200Response([void updates(GetGuardRatings200ResponseBuilder b)]) = _$GetGuardRatings200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetGuardRatings200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetGuardRatings200Response> get serializer => _$GetGuardRatings200ResponseSerializer();
}

class _$GetGuardRatings200ResponseSerializer implements PrimitiveSerializer<GetGuardRatings200Response> {
  @override
  final Iterable<Type> types = const [GetGuardRatings200Response, _$GetGuardRatings200Response];

  @override
  final String wireName = r'GetGuardRatings200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetGuardRatings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(GuardRatings),
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
    GetGuardRatings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetGuardRatings200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(GuardRatings),
          ) as GuardRatings;
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
  GetGuardRatings200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetGuardRatings200ResponseBuilder();
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

