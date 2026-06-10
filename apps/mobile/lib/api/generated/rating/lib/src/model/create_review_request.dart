//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_review_request.g.dart';

/// CreateReviewRequest
///
/// Properties:
/// * [overallRating] 
/// * [punctuality] 
/// * [professionalism] 
/// * [communication] 
/// * [appearance] 
/// * [reviewText] 
@BuiltValue()
abstract class CreateReviewRequest implements Built<CreateReviewRequest, CreateReviewRequestBuilder> {
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

  CreateReviewRequest._();

  factory CreateReviewRequest([void updates(CreateReviewRequestBuilder b)]) = _$CreateReviewRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateReviewRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateReviewRequest> get serializer => _$CreateReviewRequestSerializer();
}

class _$CreateReviewRequestSerializer implements PrimitiveSerializer<CreateReviewRequest> {
  @override
  final Iterable<Type> types = const [CreateReviewRequest, _$CreateReviewRequest];

  @override
  final String wireName = r'CreateReviewRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateReviewRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateReviewRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateReviewRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateReviewRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateReviewRequestBuilder();
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

