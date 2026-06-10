//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_rating_api/src/model/rating_summary.dart';
import 'package:pguard_rating_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_internal_rating_summary200_response.g.dart';

/// GetInternalRatingSummary200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetInternalRatingSummary200Response implements ApiResponseEnvelope, Built<GetInternalRatingSummary200Response, GetInternalRatingSummary200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  RatingSummary? get data;

  GetInternalRatingSummary200Response._();

  factory GetInternalRatingSummary200Response([void updates(GetInternalRatingSummary200ResponseBuilder b)]) = _$GetInternalRatingSummary200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetInternalRatingSummary200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetInternalRatingSummary200Response> get serializer => _$GetInternalRatingSummary200ResponseSerializer();
}

class _$GetInternalRatingSummary200ResponseSerializer implements PrimitiveSerializer<GetInternalRatingSummary200Response> {
  @override
  final Iterable<Type> types = const [GetInternalRatingSummary200Response, _$GetInternalRatingSummary200Response];

  @override
  final String wireName = r'GetInternalRatingSummary200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetInternalRatingSummary200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(RatingSummary),
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
    GetInternalRatingSummary200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetInternalRatingSummary200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RatingSummary),
          ) as RatingSummary;
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
  GetInternalRatingSummary200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetInternalRatingSummary200ResponseBuilder();
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

