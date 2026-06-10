//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'attachment.g.dart';

/// Attachment
///
/// Properties:
/// * [id] 
/// * [chatId] - The conversation this attachment belongs to (= `conversation_id`).
/// * [fileKey] - Object key `chat/{chat_id}/{uuid}.{ext}` (internal; never the bucket URL).
/// * [fileUrl] - Short-lived presigned download URL (TTL 1h), regenerated on each GET.
/// * [fileSize] - Bytes.
/// * [mimeType] 
/// * [createdAt] 
@BuiltValue()
abstract class Attachment implements Built<Attachment, AttachmentBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The conversation this attachment belongs to (= `conversation_id`).
  @BuiltValueField(wireName: r'chat_id')
  String get chatId;

  /// Object key `chat/{chat_id}/{uuid}.{ext}` (internal; never the bucket URL).
  @BuiltValueField(wireName: r'file_key')
  String get fileKey;

  /// Short-lived presigned download URL (TTL 1h), regenerated on each GET.
  @BuiltValueField(wireName: r'file_url')
  String get fileUrl;

  /// Bytes.
  @BuiltValueField(wireName: r'file_size')
  int? get fileSize;

  @BuiltValueField(wireName: r'mime_type')
  String get mimeType;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  Attachment._();

  factory Attachment([void updates(AttachmentBuilder b)]) = _$Attachment;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AttachmentBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Attachment> get serializer => _$AttachmentSerializer();
}

class _$AttachmentSerializer implements PrimitiveSerializer<Attachment> {
  @override
  final Iterable<Type> types = const [Attachment, _$Attachment];

  @override
  final String wireName = r'Attachment';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Attachment object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'chat_id';
    yield serializers.serialize(
      object.chatId,
      specifiedType: const FullType(String),
    );
    yield r'file_key';
    yield serializers.serialize(
      object.fileKey,
      specifiedType: const FullType(String),
    );
    yield r'file_url';
    yield serializers.serialize(
      object.fileUrl,
      specifiedType: const FullType(String),
    );
    if (object.fileSize != null) {
      yield r'file_size';
      yield serializers.serialize(
        object.fileSize,
        specifiedType: const FullType(int),
      );
    }
    yield r'mime_type';
    yield serializers.serialize(
      object.mimeType,
      specifiedType: const FullType(String),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Attachment object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AttachmentBuilder result,
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
        case r'chat_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.chatId = valueDes;
          break;
        case r'file_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fileKey = valueDes;
          break;
        case r'file_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fileUrl = valueDes;
          break;
        case r'file_size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.fileSize = valueDes;
          break;
        case r'mime_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mimeType = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Attachment deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AttachmentBuilder();
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

