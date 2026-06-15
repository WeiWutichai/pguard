//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/api_response_envelope.dart';
import 'package:pguard_notification_api/src/model/broadcast.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_broadcast200_response.g.dart';

/// CreateBroadcast200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class CreateBroadcast200Response implements ApiResponseEnvelope, Built<CreateBroadcast200Response, CreateBroadcast200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  Broadcast? get data;

  CreateBroadcast200Response._();

  factory CreateBroadcast200Response([void updates(CreateBroadcast200ResponseBuilder b)]) = _$CreateBroadcast200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateBroadcast200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateBroadcast200Response> get serializer => _$CreateBroadcast200ResponseSerializer();
}

class _$CreateBroadcast200ResponseSerializer implements PrimitiveSerializer<CreateBroadcast200Response> {
  @override
  final Iterable<Type> types = const [CreateBroadcast200Response, _$CreateBroadcast200Response];

  @override
  final String wireName = r'CreateBroadcast200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateBroadcast200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(Broadcast),
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
    CreateBroadcast200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateBroadcast200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Broadcast),
          ) as Broadcast;
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
  CreateBroadcast200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateBroadcast200ResponseBuilder();
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

