//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'submit_review200_response_all_of_data.g.dart';

/// SubmitReview200ResponseAllOfData
///
/// Properties:
/// * [id] 
@BuiltValue()
abstract class SubmitReview200ResponseAllOfData implements Built<SubmitReview200ResponseAllOfData, SubmitReview200ResponseAllOfDataBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  SubmitReview200ResponseAllOfData._();

  factory SubmitReview200ResponseAllOfData([void updates(SubmitReview200ResponseAllOfDataBuilder b)]) = _$SubmitReview200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SubmitReview200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SubmitReview200ResponseAllOfData> get serializer => _$SubmitReview200ResponseAllOfDataSerializer();
}

class _$SubmitReview200ResponseAllOfDataSerializer implements PrimitiveSerializer<SubmitReview200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [SubmitReview200ResponseAllOfData, _$SubmitReview200ResponseAllOfData];

  @override
  final String wireName = r'SubmitReview200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SubmitReview200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SubmitReview200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SubmitReview200ResponseAllOfDataBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SubmitReview200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SubmitReview200ResponseAllOfDataBuilder();
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

