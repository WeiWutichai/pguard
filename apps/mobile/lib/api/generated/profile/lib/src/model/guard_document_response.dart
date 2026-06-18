//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_document_response.g.dart';

/// The result of a guard-document upload/read: the canonical document type + a short-lived (1h) presigned GET URL for the stored image. The raw S3 key is NEVER exposed. 
///
/// Properties:
/// * [documentType] 
/// * [downloadUrl] - Presigned GET URL (expires in ~1h).
@BuiltValue()
abstract class GuardDocumentResponse implements Built<GuardDocumentResponse, GuardDocumentResponseBuilder> {
  @BuiltValueField(wireName: r'document_type')
  String get documentType;

  /// Presigned GET URL (expires in ~1h).
  @BuiltValueField(wireName: r'download_url')
  String get downloadUrl;

  GuardDocumentResponse._();

  factory GuardDocumentResponse([void updates(GuardDocumentResponseBuilder b)]) = _$GuardDocumentResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuardDocumentResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardDocumentResponse> get serializer => _$GuardDocumentResponseSerializer();
}

class _$GuardDocumentResponseSerializer implements PrimitiveSerializer<GuardDocumentResponse> {
  @override
  final Iterable<Type> types = const [GuardDocumentResponse, _$GuardDocumentResponse];

  @override
  final String wireName = r'GuardDocumentResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardDocumentResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'document_type';
    yield serializers.serialize(
      object.documentType,
      specifiedType: const FullType(String),
    );
    yield r'download_url';
    yield serializers.serialize(
      object.downloadUrl,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuardDocumentResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardDocumentResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'document_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.documentType = valueDes;
          break;
        case r'download_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.downloadUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuardDocumentResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuardDocumentResponseBuilder();
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

