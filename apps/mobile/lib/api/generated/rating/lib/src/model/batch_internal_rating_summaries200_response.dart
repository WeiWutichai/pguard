//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_rating_api/src/model/rating_summary_batch_item.dart';
import 'package:pguard_rating_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'batch_internal_rating_summaries200_response.g.dart';

/// BatchInternalRatingSummaries200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class BatchInternalRatingSummaries200Response implements ApiResponseEnvelope, Built<BatchInternalRatingSummaries200Response, BatchInternalRatingSummaries200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<RatingSummaryBatchItem>? get data;

  BatchInternalRatingSummaries200Response._();

  factory BatchInternalRatingSummaries200Response([void updates(BatchInternalRatingSummaries200ResponseBuilder b)]) = _$BatchInternalRatingSummaries200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BatchInternalRatingSummaries200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BatchInternalRatingSummaries200Response> get serializer => _$BatchInternalRatingSummaries200ResponseSerializer();
}

class _$BatchInternalRatingSummaries200ResponseSerializer implements PrimitiveSerializer<BatchInternalRatingSummaries200Response> {
  @override
  final Iterable<Type> types = const [BatchInternalRatingSummaries200Response, _$BatchInternalRatingSummaries200Response];

  @override
  final String wireName = r'BatchInternalRatingSummaries200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BatchInternalRatingSummaries200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(RatingSummaryBatchItem)]),
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
    BatchInternalRatingSummaries200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BatchInternalRatingSummaries200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RatingSummaryBatchItem)]),
          ) as BuiltList<RatingSummaryBatchItem>;
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
  BatchInternalRatingSummaries200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BatchInternalRatingSummaries200ResponseBuilder();
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

