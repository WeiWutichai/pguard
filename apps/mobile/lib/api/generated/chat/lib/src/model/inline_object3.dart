//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'inline_object3.g.dart';

/// InlineObject3
///
/// Properties:
/// * [success] 
@BuiltValue()
abstract class InlineObject3 implements Built<InlineObject3, InlineObject3Builder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  InlineObject3._();

  factory InlineObject3([void updates(InlineObject3Builder b)]) = _$InlineObject3;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InlineObject3Builder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InlineObject3> get serializer => _$InlineObject3Serializer();
}

class _$InlineObject3Serializer implements PrimitiveSerializer<InlineObject3> {
  @override
  final Iterable<Type> types = const [InlineObject3, _$InlineObject3];

  @override
  final String wireName = r'InlineObject3';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InlineObject3 object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.success != null) {
      yield r'success';
      yield serializers.serialize(
        object.success,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InlineObject3 object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InlineObject3Builder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InlineObject3 deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InlineObject3Builder();
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

