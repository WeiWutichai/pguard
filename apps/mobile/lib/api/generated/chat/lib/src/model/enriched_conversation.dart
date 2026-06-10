//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enriched_conversation.g.dart';

/// EnrichedConversation
///
/// Properties:
/// * [id] 
/// * [requestId] 
/// * [createdAt] 
/// * [participantId] - Counterpart user id (the participant whose role differs from `acting_role`).
/// * [participantName] 
/// * [participantAvatar] 
/// * [lastMessage] 
/// * [lastMessageAt] 
/// * [unreadCount] - Messages from the counterpart role newer than the caller's read receipt.
/// * [requestStatus] 
@BuiltValue()
abstract class EnrichedConversation implements Built<EnrichedConversation, EnrichedConversationBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'request_id')
  String get requestId;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  /// Counterpart user id (the participant whose role differs from `acting_role`).
  @BuiltValueField(wireName: r'participant_id')
  String? get participantId;

  @BuiltValueField(wireName: r'participant_name')
  String? get participantName;

  @BuiltValueField(wireName: r'participant_avatar')
  String? get participantAvatar;

  @BuiltValueField(wireName: r'last_message')
  String? get lastMessage;

  @BuiltValueField(wireName: r'last_message_at')
  DateTime? get lastMessageAt;

  /// Messages from the counterpart role newer than the caller's read receipt.
  @BuiltValueField(wireName: r'unread_count')
  int? get unreadCount;

  @BuiltValueField(wireName: r'request_status')
  String? get requestStatus;

  EnrichedConversation._();

  factory EnrichedConversation([void updates(EnrichedConversationBuilder b)]) = _$EnrichedConversation;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichedConversationBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichedConversation> get serializer => _$EnrichedConversationSerializer();
}

class _$EnrichedConversationSerializer implements PrimitiveSerializer<EnrichedConversation> {
  @override
  final Iterable<Type> types = const [EnrichedConversation, _$EnrichedConversation];

  @override
  final String wireName = r'EnrichedConversation';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichedConversation object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'request_id';
    yield serializers.serialize(
      object.requestId,
      specifiedType: const FullType(String),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.participantId != null) {
      yield r'participant_id';
      yield serializers.serialize(
        object.participantId,
        specifiedType: const FullType(String),
      );
    }
    if (object.participantName != null) {
      yield r'participant_name';
      yield serializers.serialize(
        object.participantName,
        specifiedType: const FullType(String),
      );
    }
    if (object.participantAvatar != null) {
      yield r'participant_avatar';
      yield serializers.serialize(
        object.participantAvatar,
        specifiedType: const FullType(String),
      );
    }
    if (object.lastMessage != null) {
      yield r'last_message';
      yield serializers.serialize(
        object.lastMessage,
        specifiedType: const FullType(String),
      );
    }
    if (object.lastMessageAt != null) {
      yield r'last_message_at';
      yield serializers.serialize(
        object.lastMessageAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.unreadCount != null) {
      yield r'unread_count';
      yield serializers.serialize(
        object.unreadCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.requestStatus != null) {
      yield r'request_status';
      yield serializers.serialize(
        object.requestStatus,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichedConversation object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichedConversationBuilder result,
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
        case r'request_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestId = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'participant_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.participantId = valueDes;
          break;
        case r'participant_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.participantName = valueDes;
          break;
        case r'participant_avatar':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.participantAvatar = valueDes;
          break;
        case r'last_message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastMessage = valueDes;
          break;
        case r'last_message_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastMessageAt = valueDes;
          break;
        case r'unread_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.unreadCount = valueDes;
          break;
        case r'request_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestStatus = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichedConversation deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichedConversationBuilder();
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

