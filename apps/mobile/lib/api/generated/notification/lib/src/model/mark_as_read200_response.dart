//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/notification_log.dart';
import 'package:pguard_notification_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'mark_as_read200_response.g.dart';

/// MarkAsRead200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class MarkAsRead200Response implements ApiResponseEnvelope, Built<MarkAsRead200Response, MarkAsRead200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  NotificationLog? get data;

  MarkAsRead200Response._();

  factory MarkAsRead200Response([void updates(MarkAsRead200ResponseBuilder b)]) = _$MarkAsRead200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MarkAsRead200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MarkAsRead200Response> get serializer => _$MarkAsRead200ResponseSerializer();
}

class _$MarkAsRead200ResponseSerializer implements PrimitiveSerializer<MarkAsRead200Response> {
  @override
  final Iterable<Type> types = const [MarkAsRead200Response, _$MarkAsRead200Response];

  @override
  final String wireName = r'MarkAsRead200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MarkAsRead200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(NotificationLog),
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
    MarkAsRead200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MarkAsRead200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NotificationLog),
          ) as NotificationLog;
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
  MarkAsRead200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MarkAsRead200ResponseBuilder();
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

