//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_profile_api/src/model/document_expiry.dart';
import 'package:pguard_profile_api/src/model/expiring_document_buckets.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'expiring_documents_response.g.dart';

/// The admin expiring-documents payload: the `documents` list (filtered to the requested `window`, soonest first) plus the window-independent `buckets`. 
///
/// Properties:
/// * [documents] 
/// * [buckets] 
@BuiltValue()
abstract class ExpiringDocumentsResponse implements Built<ExpiringDocumentsResponse, ExpiringDocumentsResponseBuilder> {
  @BuiltValueField(wireName: r'documents')
  BuiltList<DocumentExpiry> get documents;

  @BuiltValueField(wireName: r'buckets')
  ExpiringDocumentBuckets get buckets;

  ExpiringDocumentsResponse._();

  factory ExpiringDocumentsResponse([void updates(ExpiringDocumentsResponseBuilder b)]) = _$ExpiringDocumentsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ExpiringDocumentsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ExpiringDocumentsResponse> get serializer => _$ExpiringDocumentsResponseSerializer();
}

class _$ExpiringDocumentsResponseSerializer implements PrimitiveSerializer<ExpiringDocumentsResponse> {
  @override
  final Iterable<Type> types = const [ExpiringDocumentsResponse, _$ExpiringDocumentsResponse];

  @override
  final String wireName = r'ExpiringDocumentsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ExpiringDocumentsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'documents';
    yield serializers.serialize(
      object.documents,
      specifiedType: const FullType(BuiltList, [FullType(DocumentExpiry)]),
    );
    yield r'buckets';
    yield serializers.serialize(
      object.buckets,
      specifiedType: const FullType(ExpiringDocumentBuckets),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ExpiringDocumentsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ExpiringDocumentsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'documents':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DocumentExpiry)]),
          ) as BuiltList<DocumentExpiry>;
          result.documents.replace(valueDes);
          break;
        case r'buckets':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ExpiringDocumentBuckets),
          ) as ExpiringDocumentBuckets;
          result.buckets.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ExpiringDocumentsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ExpiringDocumentsResponseBuilder();
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

