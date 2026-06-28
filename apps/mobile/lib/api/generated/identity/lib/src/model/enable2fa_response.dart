//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enable2fa_response.g.dart';

/// One-time recovery codes — shown ONCE, never retrievable again.
///
/// Properties:
/// * [recoveryCodes] 
@BuiltValue()
abstract class Enable2faResponse implements Built<Enable2faResponse, Enable2faResponseBuilder> {
  @BuiltValueField(wireName: r'recovery_codes')
  BuiltList<String> get recoveryCodes;

  Enable2faResponse._();

  factory Enable2faResponse([void updates(Enable2faResponseBuilder b)]) = _$Enable2faResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(Enable2faResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Enable2faResponse> get serializer => _$Enable2faResponseSerializer();
}

class _$Enable2faResponseSerializer implements PrimitiveSerializer<Enable2faResponse> {
  @override
  final Iterable<Type> types = const [Enable2faResponse, _$Enable2faResponse];

  @override
  final String wireName = r'Enable2faResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Enable2faResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'recovery_codes';
    yield serializers.serialize(
      object.recoveryCodes,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Enable2faResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required Enable2faResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'recovery_codes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.recoveryCodes.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Enable2faResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = Enable2faResponseBuilder();
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

