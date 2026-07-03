//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'reset_pin200_response_all_of_data.g.dart';

/// ResetPin200ResponseAllOfData
///
/// Properties:
/// * [pinReset] 
@BuiltValue()
abstract class ResetPin200ResponseAllOfData implements Built<ResetPin200ResponseAllOfData, ResetPin200ResponseAllOfDataBuilder> {
  @BuiltValueField(wireName: r'pin_reset')
  bool? get pinReset;

  ResetPin200ResponseAllOfData._();

  factory ResetPin200ResponseAllOfData([void updates(ResetPin200ResponseAllOfDataBuilder b)]) = _$ResetPin200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ResetPin200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ResetPin200ResponseAllOfData> get serializer => _$ResetPin200ResponseAllOfDataSerializer();
}

class _$ResetPin200ResponseAllOfDataSerializer implements PrimitiveSerializer<ResetPin200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [ResetPin200ResponseAllOfData, _$ResetPin200ResponseAllOfData];

  @override
  final String wireName = r'ResetPin200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ResetPin200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.pinReset != null) {
      yield r'pin_reset';
      yield serializers.serialize(
        object.pinReset,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ResetPin200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ResetPin200ResponseAllOfDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pin_reset':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.pinReset = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ResetPin200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ResetPin200ResponseAllOfDataBuilder();
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

