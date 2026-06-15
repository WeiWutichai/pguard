//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/notification_type.dart';
import 'package:pguard_notification_api/src/model/broadcast_status.dart';
import 'package:pguard_notification_api/src/model/audience.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'broadcast.g.dart';

/// Broadcast
///
/// Properties:
/// * [id] 
/// * [audience] 
/// * [title] 
/// * [body] 
/// * [notificationType] 
/// * [status] 
/// * [scheduledAt] 
/// * [recipientCount] 
/// * [createdBy] 
/// * [createdAt] 
/// * [sentAt] 
@BuiltValue()
abstract class Broadcast implements Built<Broadcast, BroadcastBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'audience')
  Audience get audience;
  // enum audienceEnum {  all,  guards,  customers,  };

  @BuiltValueField(wireName: r'title')
  String get title;

  @BuiltValueField(wireName: r'body')
  String get body;

  @BuiltValueField(wireName: r'notification_type')
  NotificationType get notificationType;
  // enum notificationTypeEnum {  booking_created,  guard_assigned,  guard_en_route,  guard_arrived,  booking_completed,  booking_cancelled,  chat_message,  system,  };

  @BuiltValueField(wireName: r'status')
  BroadcastStatus get status;
  // enum statusEnum {  draft,  scheduled,  sent,  };

  @BuiltValueField(wireName: r'scheduled_at')
  DateTime? get scheduledAt;

  @BuiltValueField(wireName: r'recipient_count')
  int get recipientCount;

  @BuiltValueField(wireName: r'created_by')
  String get createdBy;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'sent_at')
  DateTime? get sentAt;

  Broadcast._();

  factory Broadcast([void updates(BroadcastBuilder b)]) = _$Broadcast;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BroadcastBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Broadcast> get serializer => _$BroadcastSerializer();
}

class _$BroadcastSerializer implements PrimitiveSerializer<Broadcast> {
  @override
  final Iterable<Type> types = const [Broadcast, _$Broadcast];

  @override
  final String wireName = r'Broadcast';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Broadcast object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'audience';
    yield serializers.serialize(
      object.audience,
      specifiedType: const FullType(Audience),
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
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(BroadcastStatus),
    );
    if (object.scheduledAt != null) {
      yield r'scheduled_at';
      yield serializers.serialize(
        object.scheduledAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'recipient_count';
    yield serializers.serialize(
      object.recipientCount,
      specifiedType: const FullType(int),
    );
    yield r'created_by';
    yield serializers.serialize(
      object.createdBy,
      specifiedType: const FullType(String),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.sentAt != null) {
      yield r'sent_at';
      yield serializers.serialize(
        object.sentAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Broadcast object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BroadcastBuilder result,
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
        case r'audience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Audience),
          ) as Audience;
          result.audience = valueDes;
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
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BroadcastStatus),
          ) as BroadcastStatus;
          result.status = valueDes;
          break;
        case r'scheduled_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.scheduledAt = valueDes;
          break;
        case r'recipient_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.recipientCount = valueDes;
          break;
        case r'created_by':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.createdBy = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'sent_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.sentAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Broadcast deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BroadcastBuilder();
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

