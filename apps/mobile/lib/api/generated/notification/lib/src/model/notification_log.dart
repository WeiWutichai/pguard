//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/notification_type.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_log.g.dart';

/// NotificationLog
///
/// Properties:
/// * [id] 
/// * [userId] 
/// * [title] 
/// * [body] 
/// * [notificationType] 
/// * [payload] 
/// * [isRead] 
/// * [sentAt] 
/// * [readAt] 
@BuiltValue()
abstract class NotificationLog implements Built<NotificationLog, NotificationLogBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'user_id')
  String get userId;

  @BuiltValueField(wireName: r'title')
  String get title;

  @BuiltValueField(wireName: r'body')
  String get body;

  @BuiltValueField(wireName: r'notification_type')
  NotificationType get notificationType;
  // enum notificationTypeEnum {  booking_created,  guard_assigned,  guard_en_route,  guard_arrived,  booking_completed,  booking_cancelled,  chat_message,  system,  };

  @BuiltValueField(wireName: r'payload')
  BuiltMap<String, JsonObject?>? get payload;

  @BuiltValueField(wireName: r'is_read')
  bool get isRead;

  @BuiltValueField(wireName: r'sent_at')
  DateTime get sentAt;

  @BuiltValueField(wireName: r'read_at')
  DateTime? get readAt;

  NotificationLog._();

  factory NotificationLog([void updates(NotificationLogBuilder b)]) = _$NotificationLog;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationLogBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationLog> get serializer => _$NotificationLogSerializer();
}

class _$NotificationLogSerializer implements PrimitiveSerializer<NotificationLog> {
  @override
  final Iterable<Type> types = const [NotificationLog, _$NotificationLog];

  @override
  final String wireName = r'NotificationLog';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationLog object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    yield r'body';
    yield serializers.serialize(
      object.body,
      specifiedType: const FullType(String),
    );
    yield r'notification_type';
    yield serializers.serialize(
      object.notificationType,
      specifiedType: const FullType(NotificationType),
    );
    if (object.payload != null) {
      yield r'payload';
      yield serializers.serialize(
        object.payload,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
      );
    }
    yield r'is_read';
    yield serializers.serialize(
      object.isRead,
      specifiedType: const FullType(bool),
    );
    yield r'sent_at';
    yield serializers.serialize(
      object.sentAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.readAt != null) {
      yield r'read_at';
      yield serializers.serialize(
        object.readAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationLog object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationLogBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'body':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.body = valueDes;
          break;
        case r'notification_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NotificationType),
          ) as NotificationType;
          result.notificationType = valueDes;
          break;
        case r'payload':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>;
          result.payload.replace(valueDes);
          break;
        case r'is_read':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isRead = valueDes;
          break;
        case r'sent_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.sentAt = valueDes;
          break;
        case r'read_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.readAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationLog deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationLogBuilder();
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

