//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/notification_log.dart';
import 'package:pguard_notification_api/src/model/api_response_envelope.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_notifications200_response.g.dart';

/// ListNotifications200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListNotifications200Response implements ApiResponseEnvelope, Built<ListNotifications200Response, ListNotifications200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<NotificationLog>? get data;

  ListNotifications200Response._();

  factory ListNotifications200Response([void updates(ListNotifications200ResponseBuilder b)]) = _$ListNotifications200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListNotifications200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListNotifications200Response> get serializer => _$ListNotifications200ResponseSerializer();
}

class _$ListNotifications200ResponseSerializer implements PrimitiveSerializer<ListNotifications200Response> {
  @override
  final Iterable<Type> types = const [ListNotifications200Response, _$ListNotifications200Response];

  @override
  final String wireName = r'ListNotifications200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListNotifications200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(NotificationLog)]),
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
    ListNotifications200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListNotifications200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(NotificationLog)]),
          ) as BuiltList<NotificationLog>;
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
  ListNotifications200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListNotifications200ResponseBuilder();
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

