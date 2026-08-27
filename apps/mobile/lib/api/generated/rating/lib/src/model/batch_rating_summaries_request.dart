//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'batch_rating_summaries_request.g.dart';

/// BatchRatingSummariesRequest
///
/// Properties:
/// * [ids] - The guard ids to summarise. Duplicate/unknown ids are harmless (omitted).
@BuiltValue()
abstract class BatchRatingSummariesRequest implements Built<BatchRatingSummariesRequest, BatchRatingSummariesRequestBuilder> {
  /// The guard ids to summarise. Duplicate/unknown ids are harmless (omitted).
  @BuiltValueField(wireName: r'ids')
  BuiltList<String> get ids;

  BatchRatingSummariesRequest._();

  factory BatchRatingSummariesRequest([void updates(BatchRatingSummariesRequestBuilder b)]) = _$BatchRatingSummariesRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BatchRatingSummariesRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BatchRatingSummariesRequest> get serializer => _$BatchRatingSummariesRequestSerializer();
}

class _$BatchRatingSummariesRequestSerializer implements PrimitiveSerializer<BatchRatingSummariesRequest> {
  @override
  final Iterable<Type> types = const [BatchRatingSummariesRequest, _$BatchRatingSummariesRequest];

  @override
  final String wireName = r'BatchRatingSummariesRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BatchRatingSummariesRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'ids';
    yield serializers.serialize(
      object.ids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BatchRatingSummariesRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BatchRatingSummariesRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.ids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BatchRatingSummariesRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BatchRatingSummariesRequestBuilder();
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

