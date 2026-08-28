//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rating_summary_batch_item.g.dart';

/// One guard's summary in the batch response. Field names (`average_rating`, `review_count`) match the shared discovery contract consumed by booking's discovery_client — deliberately distinct from the single-endpoint `RatingSummary` (`average`, `count`). 
///
/// Properties:
/// * [guardId] 
/// * [averageRating] - AVG of visible overall ratings, rounded to 2 dp. Present in every returned row.
/// * [reviewCount] 
@BuiltValue()
abstract class RatingSummaryBatchItem implements Built<RatingSummaryBatchItem, RatingSummaryBatchItemBuilder> {
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  /// AVG of visible overall ratings, rounded to 2 dp. Present in every returned row.
  @BuiltValueField(wireName: r'average_rating')
  String? get averageRating;

  @BuiltValueField(wireName: r'review_count')
  int get reviewCount;

  RatingSummaryBatchItem._();

  factory RatingSummaryBatchItem([void updates(RatingSummaryBatchItemBuilder b)]) = _$RatingSummaryBatchItem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RatingSummaryBatchItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RatingSummaryBatchItem> get serializer => _$RatingSummaryBatchItemSerializer();
}

class _$RatingSummaryBatchItemSerializer implements PrimitiveSerializer<RatingSummaryBatchItem> {
  @override
  final Iterable<Type> types = const [RatingSummaryBatchItem, _$RatingSummaryBatchItem];

  @override
  final String wireName = r'RatingSummaryBatchItem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RatingSummaryBatchItem object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    if (object.averageRating != null) {
      yield r'average_rating';
      yield serializers.serialize(
        object.averageRating,
        specifiedType: const FullType(String),
      );
    }
    yield r'review_count';
    yield serializers.serialize(
      object.reviewCount,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RatingSummaryBatchItem object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RatingSummaryBatchItemBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'average_rating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.averageRating = valueDes;
          break;
        case r'review_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.reviewCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RatingSummaryBatchItem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RatingSummaryBatchItemBuilder();
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

