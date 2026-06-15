//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/api_response_envelope.dart';
import 'package:pguard_notification_api/src/model/automation_rule.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_rule200_response.g.dart';

/// CreateRule200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class CreateRule200Response implements ApiResponseEnvelope, Built<CreateRule200Response, CreateRule200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  AutomationRule? get data;

  CreateRule200Response._();

  factory CreateRule200Response([void updates(CreateRule200ResponseBuilder b)]) = _$CreateRule200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateRule200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateRule200Response> get serializer => _$CreateRule200ResponseSerializer();
}

class _$CreateRule200ResponseSerializer implements PrimitiveSerializer<CreateRule200Response> {
  @override
  final Iterable<Type> types = const [CreateRule200Response, _$CreateRule200Response];

  @override
  final String wireName = r'CreateRule200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateRule200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(AutomationRule),
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
    CreateRule200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateRule200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AutomationRule),
          ) as AutomationRule;
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
  CreateRule200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateRule200ResponseBuilder();
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

