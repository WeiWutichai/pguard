//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_identity_api/src/model/enable2fa_response.dart';
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enable2fa200_response.g.dart';

/// Enable2fa200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class Enable2fa200Response implements ApiResponseEnvelope, Built<Enable2fa200Response, Enable2fa200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  Enable2faResponse? get data;

  Enable2fa200Response._();

  factory Enable2fa200Response([void updates(Enable2fa200ResponseBuilder b)]) = _$Enable2fa200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(Enable2fa200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Enable2fa200Response> get serializer => _$Enable2fa200ResponseSerializer();
}

class _$Enable2fa200ResponseSerializer implements PrimitiveSerializer<Enable2fa200Response> {
  @override
  final Iterable<Type> types = const [Enable2fa200Response, _$Enable2fa200Response];

  @override
  final String wireName = r'Enable2fa200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Enable2fa200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(Enable2faResponse),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
    yield r'success';
    yield serializers.serialize(
      object.success,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Enable2fa200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required Enable2fa200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Enable2faResponse),
          ) as Enable2faResponse;
          result.data.replace(valueDes);
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
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
  Enable2fa200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = Enable2fa200ResponseBuilder();
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

