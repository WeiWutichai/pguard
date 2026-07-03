//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_rating_api/src/model/review.dart';
import 'package:pguard_rating_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_own_review200_response.g.dart';

/// GetOwnReview200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetOwnReview200Response implements ApiResponseEnvelope, Built<GetOwnReview200Response, GetOwnReview200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  Review? get data;

  GetOwnReview200Response._();

  factory GetOwnReview200Response([void updates(GetOwnReview200ResponseBuilder b)]) = _$GetOwnReview200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetOwnReview200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetOwnReview200Response> get serializer => _$GetOwnReview200ResponseSerializer();
}

class _$GetOwnReview200ResponseSerializer implements PrimitiveSerializer<GetOwnReview200Response> {
  @override
  final Iterable<Type> types = const [GetOwnReview200Response, _$GetOwnReview200Response];

  @override
  final String wireName = r'GetOwnReview200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetOwnReview200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(Review),
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
    GetOwnReview200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetOwnReview200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Review),
          ) as Review;
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
  GetOwnReview200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetOwnReview200ResponseBuilder();
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

