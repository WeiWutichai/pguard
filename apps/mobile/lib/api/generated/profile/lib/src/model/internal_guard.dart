//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/guard_document_presence.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'internal_guard.g.dart';

/// The lean approved-guard row for internal discovery — deliberately NARROW (no bank/PII; least-privilege over the service-to-service wire). `full_name`/`avatar_url` power the customer's guard-selection card (the same approved-guard exposure as `GET /guards/{id}/public`; `avatar_url` is presigned by profile). `has_documents` is a profile-derived boolean — all five credential documents (id card, security license, training cert, criminal check, driver license) on file — so the customer card can show WHETHER documents exist; the documents themselves never cross this wire. 
///
/// Properties:
/// * [userId] 
/// * [fullName] 
/// * [avatarUrl] - Presigned GET URL for the guard's avatar (expires in ~1h), or null when unset.
/// * [yearsOfExperience] 
/// * [hasDocuments] - True when all five credential documents are on file (derived; passbook excluded).
/// * [documents] 
@BuiltValue()
abstract class InternalGuard implements Built<InternalGuard, InternalGuardBuilder> {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  @BuiltValueField(wireName: r'full_name')
  String? get fullName;

  /// Presigned GET URL for the guard's avatar (expires in ~1h), or null when unset.
  @BuiltValueField(wireName: r'avatar_url')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'years_of_experience')
  int? get yearsOfExperience;

  /// True when all five credential documents are on file (derived; passbook excluded).
  @BuiltValueField(wireName: r'has_documents')
  bool get hasDocuments;

  @BuiltValueField(wireName: r'documents')
  GuardDocumentPresence get documents;

  InternalGuard._();

  factory InternalGuard([void updates(InternalGuardBuilder b)]) = _$InternalGuard;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InternalGuardBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InternalGuard> get serializer => _$InternalGuardSerializer();
}

class _$InternalGuardSerializer implements PrimitiveSerializer<InternalGuard> {
  @override
  final Iterable<Type> types = const [InternalGuard, _$InternalGuard];

  @override
  final String wireName = r'InternalGuard';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InternalGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    if (object.fullName != null) {
      yield r'full_name';
      yield serializers.serialize(
        object.fullName,
        specifiedType: const FullType(String),
      );
    }
    if (object.avatarUrl != null) {
      yield r'avatar_url';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.yearsOfExperience != null) {
      yield r'years_of_experience';
      yield serializers.serialize(
        object.yearsOfExperience,
        specifiedType: const FullType(int),
      );
    }
    yield r'has_documents';
    yield serializers.serialize(
      object.hasDocuments,
      specifiedType: const FullType(bool),
    );
    yield r'documents';
    yield serializers.serialize(
      object.documents,
      specifiedType: const FullType(GuardDocumentPresence),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    InternalGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InternalGuardBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'full_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fullName = valueDes;
          break;
        case r'avatar_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
          break;
        case r'years_of_experience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.yearsOfExperience = valueDes;
          break;
        case r'has_documents':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasDocuments = valueDes;
          break;
        case r'documents':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(GuardDocumentPresence),
          ) as GuardDocumentPresence;
          result.documents.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InternalGuard deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InternalGuardBuilder();
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

