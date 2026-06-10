//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_review_visibility200_response_all_of_data.g.dart';

/// SetReviewVisibility200ResponseAllOfData
///
/// Properties:
/// * [id] 
/// * [isVisible] 
@BuiltValue()
abstract class SetReviewVisibility200ResponseAllOfData implements Built<SetReviewVisibility200ResponseAllOfData, SetReviewVisibility200ResponseAllOfDataBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'is_visible')
  bool? get isVisible;

  SetReviewVisibility200ResponseAllOfData._();

  factory SetReviewVisibility200ResponseAllOfData([void updates(SetReviewVisibility200ResponseAllOfDataBuilder b)]) = _$SetReviewVisibility200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetReviewVisibility200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetReviewVisibility200ResponseAllOfData> get serializer => _$SetReviewVisibility200ResponseAllOfDataSerializer();
}

class _$SetReviewVisibility200ResponseAllOfDataSerializer implements PrimitiveSerializer<SetReviewVisibility200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [SetReviewVisibility200ResponseAllOfData, _$SetReviewVisibility200ResponseAllOfData];

  @override
  final String wireName = r'SetReviewVisibility200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetReviewVisibility200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.isVisible != null) {
      yield r'is_visible';
      yield serializers.serialize(
        object.isVisible,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SetReviewVisibility200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetReviewVisibility200ResponseAllOfDataBuilder result,
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
  SetReviewVisibility200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetReviewVisibility200ResponseAllOfDataBuilder();
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

