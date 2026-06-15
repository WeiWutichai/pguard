//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_conversation.g.dart';

/// AdminConversation
///
/// Properties:
/// * [id] 
/// * [requestId] 
/// * [requestStatus] 
/// * [createdAt] 
/// * [participants] - Participant display names joined with \" · \".
/// * [lastMessage] 
/// * [lastMessageAt] 
/// * [messageCount] 
@BuiltValue()
abstract class AdminConversation implements Built<AdminConversation, AdminConversationBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'request_id')
  String get requestId;

  @BuiltValueField(wireName: r'request_status')
  String? get requestStatus;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  /// Participant display names joined with \" · \".
  @BuiltValueField(wireName: r'participants')
  String? get participants;

  @BuiltValueField(wireName: r'last_message')
  String? get lastMessage;

  @BuiltValueField(wireName: r'last_message_at')
  DateTime? get lastMessageAt;

  @BuiltValueField(wireName: r'message_count')
  int get messageCount;

  AdminConversation._();

  factory AdminConversation([void updates(AdminConversationBuilder b)]) = _$AdminConversation;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminConversationBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminConversation> get serializer => _$AdminConversationSerializer();
}

class _$AdminConversationSerializer implements PrimitiveSerializer<AdminConversation> {
  @override
  final Iterable<Type> types = const [AdminConversation, _$AdminConversation];

  @override
  final String wireName = r'AdminConversation';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminConversation object, {
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
    if (object.requestStatus != null) {
      yield r'request_status';
      yield serializers.serialize(
        object.requestStatus,
        specifiedType: const FullType(String),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.participants != null) {
      yield r'participants';
      yield serializers.serialize(
        object.participants,
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
    yield r'message_count';
    yield serializers.serialize(
      object.messageCount,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminConversation object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminConversationBuilder result,
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
        case r'request_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestStatus = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'participants':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.participants = valueDes;
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
        case r'message_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.messageCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminConversation deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminConversationBuilder();
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

