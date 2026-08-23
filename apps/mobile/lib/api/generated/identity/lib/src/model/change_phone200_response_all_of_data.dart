//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'change_phone200_response_all_of_data.g.dart';

/// ChangePhone200ResponseAllOfData
///
/// Properties:
/// * [phoneChanged] 
@BuiltValue()
abstract class ChangePhone200ResponseAllOfData implements Built<ChangePhone200ResponseAllOfData, ChangePhone200ResponseAllOfDataBuilder> {
  @BuiltValueField(wireName: r'phone_changed')
  bool? get phoneChanged;

  ChangePhone200ResponseAllOfData._();

  factory ChangePhone200ResponseAllOfData([void updates(ChangePhone200ResponseAllOfDataBuilder b)]) = _$ChangePhone200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ChangePhone200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ChangePhone200ResponseAllOfData> get serializer => _$ChangePhone200ResponseAllOfDataSerializer();
}

class _$ChangePhone200ResponseAllOfDataSerializer implements PrimitiveSerializer<ChangePhone200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [ChangePhone200ResponseAllOfData, _$ChangePhone200ResponseAllOfData];

  @override
  final String wireName = r'ChangePhone200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ChangePhone200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.phoneChanged != null) {
      yield r'phone_changed';
      yield serializers.serialize(
        object.phoneChanged,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ChangePhone200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ChangePhone200ResponseAllOfDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'phone_changed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.phoneChanged = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ChangePhone200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ChangePhone200ResponseAllOfDataBuilder();
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

