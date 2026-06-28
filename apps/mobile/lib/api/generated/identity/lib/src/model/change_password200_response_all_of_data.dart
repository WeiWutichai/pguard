//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'change_password200_response_all_of_data.g.dart';

/// ChangePassword200ResponseAllOfData
///
/// Properties:
/// * [passwordChanged] 
@BuiltValue()
abstract class ChangePassword200ResponseAllOfData implements Built<ChangePassword200ResponseAllOfData, ChangePassword200ResponseAllOfDataBuilder> {
  @BuiltValueField(wireName: r'password_changed')
  bool? get passwordChanged;

  ChangePassword200ResponseAllOfData._();

  factory ChangePassword200ResponseAllOfData([void updates(ChangePassword200ResponseAllOfDataBuilder b)]) = _$ChangePassword200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ChangePassword200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ChangePassword200ResponseAllOfData> get serializer => _$ChangePassword200ResponseAllOfDataSerializer();
}

class _$ChangePassword200ResponseAllOfDataSerializer implements PrimitiveSerializer<ChangePassword200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [ChangePassword200ResponseAllOfData, _$ChangePassword200ResponseAllOfData];

  @override
  final String wireName = r'ChangePassword200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ChangePassword200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.passwordChanged != null) {
      yield r'password_changed';
      yield serializers.serialize(
        object.passwordChanged,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ChangePassword200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ChangePassword200ResponseAllOfDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'password_changed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.passwordChanged = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ChangePassword200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ChangePassword200ResponseAllOfDataBuilder();
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

