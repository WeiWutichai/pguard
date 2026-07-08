//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'skip_booking200_response_all_of_data.g.dart';

/// SkipBooking200ResponseAllOfData
///
/// Properties:
/// * [skipped] 
@BuiltValue()
abstract class SkipBooking200ResponseAllOfData implements Built<SkipBooking200ResponseAllOfData, SkipBooking200ResponseAllOfDataBuilder> {
  @BuiltValueField(wireName: r'skipped')
  bool? get skipped;

  SkipBooking200ResponseAllOfData._();

  factory SkipBooking200ResponseAllOfData([void updates(SkipBooking200ResponseAllOfDataBuilder b)]) = _$SkipBooking200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SkipBooking200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SkipBooking200ResponseAllOfData> get serializer => _$SkipBooking200ResponseAllOfDataSerializer();
}

class _$SkipBooking200ResponseAllOfDataSerializer implements PrimitiveSerializer<SkipBooking200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [SkipBooking200ResponseAllOfData, _$SkipBooking200ResponseAllOfData];

  @override
  final String wireName = r'SkipBooking200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SkipBooking200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.skipped != null) {
      yield r'skipped';
      yield serializers.serialize(
        object.skipped,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SkipBooking200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SkipBooking200ResponseAllOfDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'skipped':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.skipped = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SkipBooking200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SkipBooking200ResponseAllOfDataBuilder();
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

