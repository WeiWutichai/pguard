//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_review_stats.g.dart';

/// Computed on the UNFILTERED dataset.
///
/// Properties:
/// * [total] 
/// * [visible] 
/// * [average] 
/// * [thisMonth] - Reviews created in the current calendar month (UTC) — the รีวิวเดือนนี้ card.
@BuiltValue()
abstract class AdminReviewStats implements Built<AdminReviewStats, AdminReviewStatsBuilder> {
  @BuiltValueField(wireName: r'total')
  int get total;

  @BuiltValueField(wireName: r'visible')
  int get visible;

  @BuiltValueField(wireName: r'average')
  String? get average;

  /// Reviews created in the current calendar month (UTC) — the รีวิวเดือนนี้ card.
  @BuiltValueField(wireName: r'this_month')
  int get thisMonth;

  AdminReviewStats._();

  factory AdminReviewStats([void updates(AdminReviewStatsBuilder b)]) = _$AdminReviewStats;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminReviewStatsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminReviewStats> get serializer => _$AdminReviewStatsSerializer();
}

class _$AdminReviewStatsSerializer implements PrimitiveSerializer<AdminReviewStats> {
  @override
  final Iterable<Type> types = const [AdminReviewStats, _$AdminReviewStats];

  @override
  final String wireName = r'AdminReviewStats';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminReviewStats object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(int),
    );
    yield r'visible';
    yield serializers.serialize(
      object.visible,
      specifiedType: const FullType(int),
    );
    if (object.average != null) {
      yield r'average';
      yield serializers.serialize(
        object.average,
        specifiedType: const FullType(String),
      );
    }
    yield r'this_month';
    yield serializers.serialize(
      object.thisMonth,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminReviewStats object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminReviewStatsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.total = valueDes;
          break;
        case r'visible':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.visible = valueDes;
          break;
        case r'average':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.average = valueDes;
          break;
        case r'this_month':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.thisMonth = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminReviewStats deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminReviewStatsBuilder();
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

