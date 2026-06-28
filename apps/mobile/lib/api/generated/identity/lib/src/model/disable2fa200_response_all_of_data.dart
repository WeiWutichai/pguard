//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'disable2fa200_response_all_of_data.g.dart';

/// Disable2fa200ResponseAllOfData
///
/// Properties:
/// * [twoFactorEnabled] 
@BuiltValue()
abstract class Disable2fa200ResponseAllOfData implements Built<Disable2fa200ResponseAllOfData, Disable2fa200ResponseAllOfDataBuilder> {
  @BuiltValueField(wireName: r'two_factor_enabled')
  bool? get twoFactorEnabled;

  Disable2fa200ResponseAllOfData._();

  factory Disable2fa200ResponseAllOfData([void updates(Disable2fa200ResponseAllOfDataBuilder b)]) = _$Disable2fa200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(Disable2fa200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Disable2fa200ResponseAllOfData> get serializer => _$Disable2fa200ResponseAllOfDataSerializer();
}

class _$Disable2fa200ResponseAllOfDataSerializer implements PrimitiveSerializer<Disable2fa200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [Disable2fa200ResponseAllOfData, _$Disable2fa200ResponseAllOfData];

  @override
  final String wireName = r'Disable2fa200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Disable2fa200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.twoFactorEnabled != null) {
      yield r'two_factor_enabled';
      yield serializers.serialize(
        object.twoFactorEnabled,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Disable2fa200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required Disable2fa200ResponseAllOfDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'two_factor_enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.twoFactorEnabled = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Disable2fa200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = Disable2fa200ResponseAllOfDataBuilder();
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

