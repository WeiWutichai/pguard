//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_rating_api/src/model/review.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_ratings.g.dart';

/// GuardRatings
///
/// Properties:
/// * [guardId] 
/// * [average] - AVG of visible overall ratings (exact decimal string), null if none.
/// * [count] - Total number of VISIBLE reviews (may exceed `reviews.length`, which is one page).
/// * [reviews] - The most-recent page of visible reviews (max 100), newest first.
@BuiltValue()
abstract class GuardRatings implements Built<GuardRatings, GuardRatingsBuilder> {
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  /// AVG of visible overall ratings (exact decimal string), null if none.
  @BuiltValueField(wireName: r'average')
  String? get average;

  /// Total number of VISIBLE reviews (may exceed `reviews.length`, which is one page).
  @BuiltValueField(wireName: r'count')
  int get count;

  /// The most-recent page of visible reviews (max 100), newest first.
  @BuiltValueField(wireName: r'reviews')
  BuiltList<Review> get reviews;

  GuardRatings._();

  factory GuardRatings([void updates(GuardRatingsBuilder b)]) = _$GuardRatings;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuardRatingsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardRatings> get serializer => _$GuardRatingsSerializer();
}

class _$GuardRatingsSerializer implements PrimitiveSerializer<GuardRatings> {
  @override
  final Iterable<Type> types = const [GuardRatings, _$GuardRatings];

  @override
  final String wireName = r'GuardRatings';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardRatings object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    if (object.average != null) {
      yield r'average';
      yield serializers.serialize(
        object.average,
        specifiedType: const FullType(String),
      );
    }
    yield r'count';
    yield serializers.serialize(
      object.count,
      specifiedType: const FullType(int),
    );
    yield r'reviews';
    yield serializers.serialize(
      object.reviews,
      specifiedType: const FullType(BuiltList, [FullType(Review)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuardRatings object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardRatingsBuilder result,
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
        case r'average':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.average = valueDes;
          break;
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        case r'reviews':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Review)]),
          ) as BuiltList<Review>;
          result.reviews.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuardRatings deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuardRatingsBuilder();
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

