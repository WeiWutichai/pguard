//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_rating_api/src/model/admin_review_stats.dart';
import 'package:pguard_rating_api/src/model/admin_review.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_reviews.g.dart';

/// AdminReviews
///
/// Properties:
/// * [data] 
/// * [total] 
/// * [limit] 
/// * [offset] 
/// * [stats] 
@BuiltValue()
abstract class AdminReviews implements Built<AdminReviews, AdminReviewsBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<AdminReview> get data;

  @BuiltValueField(wireName: r'total')
  int get total;

  @BuiltValueField(wireName: r'limit')
  int get limit;

  @BuiltValueField(wireName: r'offset')
  int get offset;

  @BuiltValueField(wireName: r'stats')
  AdminReviewStats get stats;

  AdminReviews._();

  factory AdminReviews([void updates(AdminReviewsBuilder b)]) = _$AdminReviews;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminReviewsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminReviews> get serializer => _$AdminReviewsSerializer();
}

class _$AdminReviewsSerializer implements PrimitiveSerializer<AdminReviews> {
  @override
  final Iterable<Type> types = const [AdminReviews, _$AdminReviews];

  @override
  final String wireName = r'AdminReviews';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminReviews object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'data';
    yield serializers.serialize(
      object.data,
      specifiedType: const FullType(BuiltList, [FullType(AdminReview)]),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(int),
    );
    yield r'limit';
    yield serializers.serialize(
      object.limit,
      specifiedType: const FullType(int),
    );
    yield r'offset';
    yield serializers.serialize(
      object.offset,
      specifiedType: const FullType(int),
    );
    yield r'stats';
    yield serializers.serialize(
      object.stats,
      specifiedType: const FullType(AdminReviewStats),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminReviews object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminReviewsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(AdminReview)]),
          ) as BuiltList<AdminReview>;
          result.data.replace(valueDes);
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.total = valueDes;
          break;
        case r'limit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.limit = valueDes;
          break;
        case r'offset':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.offset = valueDes;
          break;
        case r'stats':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AdminReviewStats),
          ) as AdminReviewStats;
          result.stats.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminReviews deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminReviewsBuilder();
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

