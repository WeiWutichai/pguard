//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_completion_request.g.dart';

/// ReviewCompletionRequest
///
/// Properties:
/// * [action] - `approve` → completed (emits booking.completed); `reject` → back to arrived.
@BuiltValue()
abstract class ReviewCompletionRequest implements Built<ReviewCompletionRequest, ReviewCompletionRequestBuilder> {
  /// `approve` → completed (emits booking.completed); `reject` → back to arrived.
  @BuiltValueField(wireName: r'action')
  ReviewCompletionRequestActionEnum get action;
  // enum actionEnum {  approve,  reject,  };

  ReviewCompletionRequest._();

  factory ReviewCompletionRequest([void updates(ReviewCompletionRequestBuilder b)]) = _$ReviewCompletionRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewCompletionRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewCompletionRequest> get serializer => _$ReviewCompletionRequestSerializer();
}

class _$ReviewCompletionRequestSerializer implements PrimitiveSerializer<ReviewCompletionRequest> {
  @override
  final Iterable<Type> types = const [ReviewCompletionRequest, _$ReviewCompletionRequest];

  @override
  final String wireName = r'ReviewCompletionRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewCompletionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'action';
    yield serializers.serialize(
      object.action,
      specifiedType: const FullType(ReviewCompletionRequestActionEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewCompletionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewCompletionRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'action':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReviewCompletionRequestActionEnum),
          ) as ReviewCompletionRequestActionEnum;
          result.action = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewCompletionRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewCompletionRequestBuilder();
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

class ReviewCompletionRequestActionEnum extends EnumClass {

  /// `approve` → completed (emits booking.completed); `reject` → back to arrived.
  @BuiltValueEnumConst(wireName: r'approve')
  static const ReviewCompletionRequestActionEnum approve = _$reviewCompletionRequestActionEnum_approve;
  /// `approve` → completed (emits booking.completed); `reject` → back to arrived.
  @BuiltValueEnumConst(wireName: r'reject')
  static const ReviewCompletionRequestActionEnum reject = _$reviewCompletionRequestActionEnum_reject;

  static Serializer<ReviewCompletionRequestActionEnum> get serializer => _$reviewCompletionRequestActionEnumSerializer;

  const ReviewCompletionRequestActionEnum._(String name): super(name);

  static BuiltSet<ReviewCompletionRequestActionEnum> get values => _$reviewCompletionRequestActionEnumValues;
  static ReviewCompletionRequestActionEnum valueOf(String name) => _$reviewCompletionRequestActionEnumValueOf(name);
}

