//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/notification_type.dart';
import 'package:pguard_notification_api/src/model/audience.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_broadcast_request.g.dart';

/// Edit a DRAFT broadcast — all fields optional (only provided fields change).
///
/// Properties:
/// * [audience] 
/// * [title] 
/// * [body] 
/// * [notificationType] 
/// * [scheduledAt] 
@BuiltValue()
abstract class UpdateBroadcastRequest implements Built<UpdateBroadcastRequest, UpdateBroadcastRequestBuilder> {
  @BuiltValueField(wireName: r'audience')
  Audience? get audience;
  // enum audienceEnum {  all,  guards,  customers,  };

  @BuiltValueField(wireName: r'title')
  String? get title;

  @BuiltValueField(wireName: r'body')
  String? get body;

  @BuiltValueField(wireName: r'notification_type')
  NotificationType? get notificationType;
  // enum notificationTypeEnum {  booking_created,  guard_assigned,  guard_en_route,  guard_arrived,  booking_completed,  booking_cancelled,  chat_message,  system,  };

  @BuiltValueField(wireName: r'scheduled_at')
  DateTime? get scheduledAt;

  UpdateBroadcastRequest._();

  factory UpdateBroadcastRequest([void updates(UpdateBroadcastRequestBuilder b)]) = _$UpdateBroadcastRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateBroadcastRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateBroadcastRequest> get serializer => _$UpdateBroadcastRequestSerializer();
}

class _$UpdateBroadcastRequestSerializer implements PrimitiveSerializer<UpdateBroadcastRequest> {
  @override
  final Iterable<Type> types = const [UpdateBroadcastRequest, _$UpdateBroadcastRequest];

  @override
  final String wireName = r'UpdateBroadcastRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateBroadcastRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.audience != null) {
      yield r'audience';
      yield serializers.serialize(
        object.audience,
        specifiedType: const FullType(Audience),
      );
    }
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType(String),
      );
    }
    if (object.body != null) {
      yield r'body';
      yield serializers.serialize(
        object.body,
        specifiedType: const FullType(String),
      );
    }
    if (object.notificationType != null) {
      yield r'notification_type';
      yield serializers.serialize(
        object.notificationType,
        specifiedType: const FullType(NotificationType),
      );
    }
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
    UpdateBroadcastRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpdateBroadcastRequestBuilder result,
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
  UpdateBroadcastRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateBroadcastRequestBuilder();
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

