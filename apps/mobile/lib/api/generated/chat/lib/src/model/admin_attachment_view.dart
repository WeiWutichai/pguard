//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_attachment_view.g.dart';

/// The resolvable bits of an attachment for the admin message view — a fresh presigned URL plus the MIME so the web renders an `<img>` thumbnail or a video indicator.
///
/// Properties:
/// * [id] 
/// * [url] - Fresh presigned download URL (TTL 1h) — the admin-viewable thumbnail/source.
/// * [mimeType] 
/// * [fileSize] - Bytes.
/// * [isVideo] - True for video/_* (web shows a video indicator vs an image thumbnail).
@BuiltValue()
abstract class AdminAttachmentView implements Built<AdminAttachmentView, AdminAttachmentViewBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Fresh presigned download URL (TTL 1h) — the admin-viewable thumbnail/source.
  @BuiltValueField(wireName: r'url')
  String get url;

  @BuiltValueField(wireName: r'mime_type')
  String get mimeType;

  /// Bytes.
  @BuiltValueField(wireName: r'file_size')
  int? get fileSize;

  /// True for video/_* (web shows a video indicator vs an image thumbnail).
  @BuiltValueField(wireName: r'is_video')
  bool get isVideo;

  AdminAttachmentView._();

  factory AdminAttachmentView([void updates(AdminAttachmentViewBuilder b)]) = _$AdminAttachmentView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminAttachmentViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminAttachmentView> get serializer => _$AdminAttachmentViewSerializer();
}

class _$AdminAttachmentViewSerializer implements PrimitiveSerializer<AdminAttachmentView> {
  @override
  final Iterable<Type> types = const [AdminAttachmentView, _$AdminAttachmentView];

  @override
  final String wireName = r'AdminAttachmentView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminAttachmentView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    yield r'mime_type';
    yield serializers.serialize(
      object.mimeType,
      specifiedType: const FullType(String),
    );
    if (object.fileSize != null) {
      yield r'file_size';
      yield serializers.serialize(
        object.fileSize,
        specifiedType: const FullType(int),
      );
    }
    yield r'is_video';
    yield serializers.serialize(
      object.isVideo,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminAttachmentView object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminAttachmentViewBuilder result,
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
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'mime_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mimeType = valueDes;
          break;
        case r'file_size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.fileSize = valueDes;
          break;
        case r'is_video':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isVideo = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminAttachmentView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminAttachmentViewBuilder();
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

