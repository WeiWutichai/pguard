//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_identity_api/src/model/disable2fa200_response_all_of_data.dart';
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'disable2fa200_response.g.dart';

/// Disable2fa200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class Disable2fa200Response implements ApiResponseEnvelope, Built<Disable2fa200Response, Disable2fa200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  Disable2fa200ResponseAllOfData? get data;

  Disable2fa200Response._();

  factory Disable2fa200Response([void updates(Disable2fa200ResponseBuilder b)]) = _$Disable2fa200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(Disable2fa200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Disable2fa200Response> get serializer => _$Disable2fa200ResponseSerializer();
}

class _$Disable2fa200ResponseSerializer implements PrimitiveSerializer<Disable2fa200Response> {
  @override
  final Iterable<Type> types = const [Disable2fa200Response, _$Disable2fa200Response];

  @override
  final String wireName = r'Disable2fa200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Disable2fa200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(Disable2fa200ResponseAllOfData),
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
    Disable2fa200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required Disable2fa200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Disable2fa200ResponseAllOfData),
          ) as Disable2fa200ResponseAllOfData;
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
  Disable2fa200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = Disable2fa200ResponseBuilder();
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

