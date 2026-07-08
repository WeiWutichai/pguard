//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'phone_status200_response_all_of_data.g.dart';

/// PhoneStatus200ResponseAllOfData
///
/// Properties:
/// * [accountExists] 
@BuiltValue()
abstract class PhoneStatus200ResponseAllOfData implements Built<PhoneStatus200ResponseAllOfData, PhoneStatus200ResponseAllOfDataBuilder> {
  @BuiltValueField(wireName: r'account_exists')
  bool? get accountExists;

  PhoneStatus200ResponseAllOfData._();

  factory PhoneStatus200ResponseAllOfData([void updates(PhoneStatus200ResponseAllOfDataBuilder b)]) = _$PhoneStatus200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhoneStatus200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhoneStatus200ResponseAllOfData> get serializer => _$PhoneStatus200ResponseAllOfDataSerializer();
}

class _$PhoneStatus200ResponseAllOfDataSerializer implements PrimitiveSerializer<PhoneStatus200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [PhoneStatus200ResponseAllOfData, _$PhoneStatus200ResponseAllOfData];

  @override
  final String wireName = r'PhoneStatus200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhoneStatus200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.accountExists != null) {
      yield r'account_exists';
      yield serializers.serialize(
        object.accountExists,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PhoneStatus200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PhoneStatus200ResponseAllOfDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'account_exists':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.accountExists = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhoneStatus200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhoneStatus200ResponseAllOfDataBuilder();
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

