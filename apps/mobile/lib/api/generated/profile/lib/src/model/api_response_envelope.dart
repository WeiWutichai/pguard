//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_envelope.g.dart';

/// Standard success envelope; concrete `data` shape is composed per-endpoint.
///
/// Properties:
/// * [success] 
/// * [error] 
@BuiltValue(instantiable: false)
abstract class ApiResponseEnvelope  {
  @BuiltValueField(wireName: r'success')
  bool get success;

  @BuiltValueField(wireName: r'error')
  String? get error;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponseEnvelope> get serializer => _$ApiResponseEnvelopeSerializer();
}

class _$ApiResponseEnvelopeSerializer implements PrimitiveSerializer<ApiResponseEnvelope> {
  @override
  final Iterable<Type> types = const [ApiResponseEnvelope];

  @override
  final String wireName = r'ApiResponseEnvelope';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponseEnvelope object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'success';
    yield serializers.serialize(
      object.success,
      specifiedType: const FullType(bool),
    );
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ApiResponseEnvelope object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  ApiResponseEnvelope deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($ApiResponseEnvelope)) as $ApiResponseEnvelope;
  }
}

/// a concrete implementation of [ApiResponseEnvelope], since [ApiResponseEnvelope] is not instantiable
@BuiltValue(instantiable: true)
abstract class $ApiResponseEnvelope implements ApiResponseEnvelope, Built<$ApiResponseEnvelope, $ApiResponseEnvelopeBuilder> {
  $ApiResponseEnvelope._();

  factory $ApiResponseEnvelope([void Function($ApiResponseEnvelopeBuilder)? updates]) = _$$ApiResponseEnvelope;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($ApiResponseEnvelopeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$ApiResponseEnvelope> get serializer => _$$ApiResponseEnvelopeSerializer();
}

class _$$ApiResponseEnvelopeSerializer implements PrimitiveSerializer<$ApiResponseEnvelope> {
  @override
  final Iterable<Type> types = const [$ApiResponseEnvelope, _$$ApiResponseEnvelope];

  @override
  final String wireName = r'$ApiResponseEnvelope';

  @override
  Object serialize(
    Serializers serializers,
    $ApiResponseEnvelope object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(ApiResponseEnvelope))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ApiResponseEnvelopeBuilder result,
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
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $ApiResponseEnvelope deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $ApiResponseEnvelopeBuilder();
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

