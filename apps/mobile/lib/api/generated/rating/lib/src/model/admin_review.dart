//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_review.g.dart';

/// AdminReview
///
/// Properties:
/// * [id] 
/// * [assignmentId] 
/// * [customerId] 
/// * [guardId] 
/// * [overallRating] 
/// * [punctuality] 
/// * [professionalism] 
/// * [communication] 
/// * [appearance] 
/// * [reviewText] 
/// * [isVisible] 
/// * [createdAt] 
@BuiltValue()
abstract class AdminReview implements Built<AdminReview, AdminReviewBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'assignment_id')
  String get assignmentId;

  @BuiltValueField(wireName: r'customer_id')
  String get customerId;

  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  @BuiltValueField(wireName: r'overall_rating')
  int get overallRating;

  @BuiltValueField(wireName: r'punctuality')
  int? get punctuality;

  @BuiltValueField(wireName: r'professionalism')
  int? get professionalism;

  @BuiltValueField(wireName: r'communication')
  int? get communication;

  @BuiltValueField(wireName: r'appearance')
  int? get appearance;

  @BuiltValueField(wireName: r'review_text')
  String? get reviewText;

  @BuiltValueField(wireName: r'is_visible')
  bool get isVisible;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  AdminReview._();

  factory AdminReview([void updates(AdminReviewBuilder b)]) = _$AdminReview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminReviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminReview> get serializer => _$AdminReviewSerializer();
}

class _$AdminReviewSerializer implements PrimitiveSerializer<AdminReview> {
  @override
  final Iterable<Type> types = const [AdminReview, _$AdminReview];

  @override
  final String wireName = r'AdminReview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminReview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'assignment_id';
    yield serializers.serialize(
      object.assignmentId,
      specifiedType: const FullType(String),
    );
    yield r'customer_id';
    yield serializers.serialize(
      object.customerId,
      specifiedType: const FullType(String),
    );
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    yield r'overall_rating';
    yield serializers.serialize(
      object.overallRating,
      specifiedType: const FullType(int),
    );
    if (object.punctuality != null) {
      yield r'punctuality';
      yield serializers.serialize(
        object.punctuality,
        specifiedType: const FullType(int),
      );
    }
    if (object.professionalism != null) {
      yield r'professionalism';
      yield serializers.serialize(
        object.professionalism,
        specifiedType: const FullType(int),
      );
    }
    if (object.communication != null) {
      yield r'communication';
      yield serializers.serialize(
        object.communication,
        specifiedType: const FullType(int),
      );
    }
    if (object.appearance != null) {
      yield r'appearance';
      yield serializers.serialize(
        object.appearance,
        specifiedType: const FullType(int),
      );
    }
    if (object.reviewText != null) {
      yield r'review_text';
      yield serializers.serialize(
        object.reviewText,
        specifiedType: const FullType(String),
      );
    }
    yield r'is_visible';
    yield serializers.serialize(
      object.isVisible,
      specifiedType: const FullType(bool),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminReview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminReviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'assignment_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.assignmentId = valueDes;
          break;
        case r'customer_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.customerId = valueDes;
          break;
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'overall_rating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.overallRating = valueDes;
          break;
        case r'punctuality':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.punctuality = valueDes;
          break;
        case r'professionalism':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.professionalism = valueDes;
          break;
        case r'communication':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.communication = valueDes;
          break;
        case r'appearance':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.appearance = valueDes;
          break;
        case r'review_text':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reviewText = valueDes;
          break;
        case r'is_visible':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isVisible = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminReview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminReviewBuilder();
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

