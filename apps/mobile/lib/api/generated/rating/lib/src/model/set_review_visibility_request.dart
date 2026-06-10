//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_review_visibility_request.g.dart';

/// SetReviewVisibilityRequest
///
/// Properties:
/// * [isVisible] 
@BuiltValue()
abstract class SetReviewVisibilityRequest implements Built<SetReviewVisibilityRequest, SetReviewVisibilityRequestBuilder> {
  @BuiltValueField(wireName: r'is_visible')
  bool get isVisible;

  SetReviewVisibilityRequest._();

  factory SetReviewVisibilityRequest([void updates(SetReviewVisibilityRequestBuilder b)]) = _$SetReviewVisibilityRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetReviewVisibilityRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetReviewVisibilityRequest> get serializer => _$SetReviewVisibilityRequestSerializer();
}

class _$SetReviewVisibilityRequestSerializer implements PrimitiveSerializer<SetReviewVisibilityRequest> {
  @override
  final Iterable<Type> types = const [SetReviewVisibilityRequest, _$SetReviewVisibilityRequest];

  @override
  final String wireName = r'SetReviewVisibilityRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetReviewVisibilityRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'is_visible';
    yield serializers.serialize(
      object.isVisible,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SetReviewVisibilityRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetReviewVisibilityRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'is_visible':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isVisible = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SetReviewVisibilityRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetReviewVisibilityRequestBuilder();
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

