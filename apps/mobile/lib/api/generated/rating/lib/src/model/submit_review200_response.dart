//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_rating_api/src/model/submit_review200_response_all_of_data.dart';
import 'package:pguard_rating_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'submit_review200_response.g.dart';

/// SubmitReview200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class SubmitReview200Response implements ApiResponseEnvelope, Built<SubmitReview200Response, SubmitReview200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  SubmitReview200ResponseAllOfData? get data;

  SubmitReview200Response._();

  factory SubmitReview200Response([void updates(SubmitReview200ResponseBuilder b)]) = _$SubmitReview200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SubmitReview200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SubmitReview200Response> get serializer => _$SubmitReview200ResponseSerializer();
}

class _$SubmitReview200ResponseSerializer implements PrimitiveSerializer<SubmitReview200Response> {
  @override
  final Iterable<Type> types = const [SubmitReview200Response, _$SubmitReview200Response];

  @override
  final String wireName = r'SubmitReview200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SubmitReview200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(SubmitReview200ResponseAllOfData),
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
    SubmitReview200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SubmitReview200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SubmitReview200ResponseAllOfData),
          ) as SubmitReview200ResponseAllOfData;
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
  SubmitReview200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SubmitReview200ResponseBuilder();
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

