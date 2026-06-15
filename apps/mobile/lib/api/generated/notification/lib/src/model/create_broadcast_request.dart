//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/notification_type.dart';
import 'package:pguard_notification_api/src/model/broadcast_mode.dart';
import 'package:pguard_notification_api/src/model/audience.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_broadcast_request.g.dart';

/// CreateBroadcastRequest
///
/// Properties:
/// * [audience] 
/// * [title] 
/// * [body] 
/// * [notificationType] - Defaults to `system` when omitted.
/// * [mode] 
/// * [scheduledAt] - Required (future) when `mode = scheduled`.
@BuiltValue()
abstract class CreateBroadcastRequest implements Built<CreateBroadcastRequest, CreateBroadcastRequestBuilder> {
  @BuiltValueField(wireName: r'audience')
  Audience get audience;
  // enum audienceEnum {  all,  guards,  customers,  };

  @BuiltValueField(wireName: r'title')
  String get title;

  @BuiltValueField(wireName: r'body')
  String get body;

  /// Defaults to `system` when omitted.
  @BuiltValueField(wireName: r'notification_type')
  NotificationType? get notificationType;
  // enum notificationTypeEnum {  booking_created,  guard_assigned,  guard_en_route,  guard_arrived,  booking_completed,  booking_cancelled,  chat_message,  system,  };

  @BuiltValueField(wireName: r'mode')
  BroadcastMode get mode;
  // enum modeEnum {  now,  draft,  scheduled,  };

  /// Required (future) when `mode = scheduled`.
  @BuiltValueField(wireName: r'scheduled_at')
  DateTime? get scheduledAt;

  CreateBroadcastRequest._();

  factory CreateBroadcastRequest([void updates(CreateBroadcastRequestBuilder b)]) = _$CreateBroadcastRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateBroadcastRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateBroadcastRequest> get serializer => _$CreateBroadcastRequestSerializer();
}

class _$CreateBroadcastRequestSerializer implements PrimitiveSerializer<CreateBroadcastRequest> {
  @override
  final Iterable<Type> types = const [CreateBroadcastRequest, _$CreateBroadcastRequest];

  @override
  final String wireName = r'CreateBroadcastRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateBroadcastRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    if (object.notificationType != null) {
      yield r'notification_type';
      yield serializers.serialize(
        object.notificationType,
        specifiedType: const FullType(NotificationType),
      );
    }
    yield r'mode';
    yield serializers.serialize(
      object.mode,
      specifiedType: const FullType(BroadcastMode),
    );
    if (object.scheduledAt != null) {
      yield r'scheduled_at';
      yield serializers.serialize(
        object.scheduledAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateBroadcastRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateBroadcastRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BroadcastMode),
          ) as BroadcastMode;
          result.mode = valueDes;
          break;
        case r'scheduled_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.scheduledAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateBroadcastRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateBroadcastRequestBuilder();
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

