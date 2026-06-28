//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_chat_api/src/model/admin_call_event.dart';
import 'package:pguard_chat_api/src/model/message_type.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_chat_api/src/model/admin_attachment_view.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_enriched_message.g.dart';

/// An admin-audit message enriched into RENDERABLE data. The raw `content` is parsed per `message_type`: text rows carry `text`; image/video rows resolve to a presigned `attachment` (with the raw `attachment_id` echoed even if resolution fails); a call-summary `system` row parses into a structured `call_event` (and `kind` becomes `call-event`). READ-ONLY (no moderation fields — Phase D).
///
/// Properties:
/// * [id] 
/// * [conversationId] 
/// * [senderId] 
/// * [senderRole] - guard | customer
/// * [messageType] 
/// * [createdAt] 
/// * [kind] - The parsed render kind the web switches on. Distinct from `message_type`: a `system` row whose content is the pinned call JSON becomes `call-event`.
/// * [text] - Plain text for a `text` message; null otherwise.
/// * [attachment] 
/// * [attachmentId] - Raw attachment id carried in a media message's `content` (echoed even if resolution fails, so the admin still sees there WAS an attachment); null for non-media.
/// * [callEvent] 
@BuiltValue()
abstract class AdminEnrichedMessage implements Built<AdminEnrichedMessage, AdminEnrichedMessageBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'conversation_id')
  String get conversationId;

  @BuiltValueField(wireName: r'sender_id')
  String get senderId;

  /// guard | customer
  @BuiltValueField(wireName: r'sender_role')
  String? get senderRole;

  @BuiltValueField(wireName: r'message_type')
  MessageType get messageType;
  // enum messageTypeEnum {  text,  image,  video,  system,  };

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  /// The parsed render kind the web switches on. Distinct from `message_type`: a `system` row whose content is the pinned call JSON becomes `call-event`.
  @BuiltValueField(wireName: r'kind')
  AdminEnrichedMessageKindEnum get kind;
  // enum kindEnum {  text,  image,  video,  call-event,  system,  unknown,  };

  /// Plain text for a `text` message; null otherwise.
  @BuiltValueField(wireName: r'text')
  String? get text;

  @BuiltValueField(wireName: r'attachment')
  AdminAttachmentView? get attachment;

  /// Raw attachment id carried in a media message's `content` (echoed even if resolution fails, so the admin still sees there WAS an attachment); null for non-media.
  @BuiltValueField(wireName: r'attachment_id')
  String? get attachmentId;

  @BuiltValueField(wireName: r'call_event')
  AdminCallEvent? get callEvent;

  AdminEnrichedMessage._();

  factory AdminEnrichedMessage([void updates(AdminEnrichedMessageBuilder b)]) = _$AdminEnrichedMessage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminEnrichedMessageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminEnrichedMessage> get serializer => _$AdminEnrichedMessageSerializer();
}

class _$AdminEnrichedMessageSerializer implements PrimitiveSerializer<AdminEnrichedMessage> {
  @override
  final Iterable<Type> types = const [AdminEnrichedMessage, _$AdminEnrichedMessage];

  @override
  final String wireName = r'AdminEnrichedMessage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminEnrichedMessage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'conversation_id';
    yield serializers.serialize(
      object.conversationId,
      specifiedType: const FullType(String),
    );
    yield r'sender_id';
    yield serializers.serialize(
      object.senderId,
      specifiedType: const FullType(String),
    );
    if (object.senderRole != null) {
      yield r'sender_role';
      yield serializers.serialize(
        object.senderRole,
        specifiedType: const FullType(String),
      );
    }
    yield r'message_type';
    yield serializers.serialize(
      object.messageType,
      specifiedType: const FullType(MessageType),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(AdminEnrichedMessageKindEnum),
    );
    if (object.text != null) {
      yield r'text';
      yield serializers.serialize(
        object.text,
        specifiedType: const FullType(String),
      );
    }
    if (object.attachment != null) {
      yield r'attachment';
      yield serializers.serialize(
        object.attachment,
        specifiedType: const FullType(AdminAttachmentView),
      );
    }
    if (object.attachmentId != null) {
      yield r'attachment_id';
      yield serializers.serialize(
        object.attachmentId,
        specifiedType: const FullType(String),
      );
    }
    if (object.callEvent != null) {
      yield r'call_event';
      yield serializers.serialize(
        object.callEvent,
        specifiedType: const FullType(AdminCallEvent),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminEnrichedMessage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminEnrichedMessageBuilder result,
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
        case r'conversation_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.conversationId = valueDes;
          break;
        case r'sender_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.senderId = valueDes;
          break;
        case r'sender_role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.senderRole = valueDes;
          break;
        case r'message_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MessageType),
          ) as MessageType;
          result.messageType = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AdminEnrichedMessageKindEnum),
          ) as AdminEnrichedMessageKindEnum;
          result.kind = valueDes;
          break;
        case r'text':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.text = valueDes;
          break;
        case r'attachment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AdminAttachmentView),
          ) as AdminAttachmentView;
          result.attachment.replace(valueDes);
          break;
        case r'attachment_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.attachmentId = valueDes;
          break;
        case r'call_event':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AdminCallEvent),
          ) as AdminCallEvent;
          result.callEvent.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminEnrichedMessage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminEnrichedMessageBuilder();
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

class AdminEnrichedMessageKindEnum extends EnumClass {

  /// The parsed render kind the web switches on. Distinct from `message_type`: a `system` row whose content is the pinned call JSON becomes `call-event`.
  @BuiltValueEnumConst(wireName: r'text')
  static const AdminEnrichedMessageKindEnum text = _$adminEnrichedMessageKindEnum_text;
  /// The parsed render kind the web switches on. Distinct from `message_type`: a `system` row whose content is the pinned call JSON becomes `call-event`.
  @BuiltValueEnumConst(wireName: r'image')
  static const AdminEnrichedMessageKindEnum image = _$adminEnrichedMessageKindEnum_image;
  /// The parsed render kind the web switches on. Distinct from `message_type`: a `system` row whose content is the pinned call JSON becomes `call-event`.
  @BuiltValueEnumConst(wireName: r'video')
  static const AdminEnrichedMessageKindEnum video = _$adminEnrichedMessageKindEnum_video;
  /// The parsed render kind the web switches on. Distinct from `message_type`: a `system` row whose content is the pinned call JSON becomes `call-event`.
  @BuiltValueEnumConst(wireName: r'call-event')
  static const AdminEnrichedMessageKindEnum callEvent = _$adminEnrichedMessageKindEnum_callEvent;
  /// The parsed render kind the web switches on. Distinct from `message_type`: a `system` row whose content is the pinned call JSON becomes `call-event`.
  @BuiltValueEnumConst(wireName: r'system')
  static const AdminEnrichedMessageKindEnum system = _$adminEnrichedMessageKindEnum_system;
  /// The parsed render kind the web switches on. Distinct from `message_type`: a `system` row whose content is the pinned call JSON becomes `call-event`.
  @BuiltValueEnumConst(wireName: r'unknown')
  static const AdminEnrichedMessageKindEnum unknown = _$adminEnrichedMessageKindEnum_unknown;

  static Serializer<AdminEnrichedMessageKindEnum> get serializer => _$adminEnrichedMessageKindEnumSerializer;

  const AdminEnrichedMessageKindEnum._(String name): super(name);

  static BuiltSet<AdminEnrichedMessageKindEnum> get values => _$adminEnrichedMessageKindEnumValues;
  static AdminEnrichedMessageKindEnum valueOf(String name) => _$adminEnrichedMessageKindEnumValueOf(name);
}

