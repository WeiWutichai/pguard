//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/date.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'document_expiry.g.dart';

/// One guard-document expiry row (the admin \"expiring documents\" surface + the owner/admin per-guard list). `days_left = expiry_date - current_date` (computed in SQL): negative = already expired, 0 = due today, positive = days until it lapses. 
///
/// Properties:
/// * [id] 
/// * [guardId] 
/// * [documentType] 
/// * [expiryDate] 
/// * [daysLeft] - expiry_date − current_date (days; negative = expired).
/// * [lastRemindedAt] 
@BuiltValue()
abstract class DocumentExpiry implements Built<DocumentExpiry, DocumentExpiryBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  @BuiltValueField(wireName: r'document_type')
  DocumentExpiryDocumentTypeEnum get documentType;
  // enum documentTypeEnum {  id_card,  security_license,  training_cert,  criminal_check,  driver_license,  };

  @BuiltValueField(wireName: r'expiry_date')
  Date get expiryDate;

  /// expiry_date − current_date (days; negative = expired).
  @BuiltValueField(wireName: r'days_left')
  int get daysLeft;

  @BuiltValueField(wireName: r'last_reminded_at')
  DateTime? get lastRemindedAt;

  DocumentExpiry._();

  factory DocumentExpiry([void updates(DocumentExpiryBuilder b)]) = _$DocumentExpiry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DocumentExpiryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DocumentExpiry> get serializer => _$DocumentExpirySerializer();
}

class _$DocumentExpirySerializer implements PrimitiveSerializer<DocumentExpiry> {
  @override
  final Iterable<Type> types = const [DocumentExpiry, _$DocumentExpiry];

  @override
  final String wireName = r'DocumentExpiry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DocumentExpiry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    yield r'document_type';
    yield serializers.serialize(
      object.documentType,
      specifiedType: const FullType(DocumentExpiryDocumentTypeEnum),
    );
    yield r'expiry_date';
    yield serializers.serialize(
      object.expiryDate,
      specifiedType: const FullType(Date),
    );
    yield r'days_left';
    yield serializers.serialize(
      object.daysLeft,
      specifiedType: const FullType(int),
    );
    if (object.lastRemindedAt != null) {
      yield r'last_reminded_at';
      yield serializers.serialize(
        object.lastRemindedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DocumentExpiry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DocumentExpiryBuilder result,
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
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'document_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DocumentExpiryDocumentTypeEnum),
          ) as DocumentExpiryDocumentTypeEnum;
          result.documentType = valueDes;
          break;
        case r'expiry_date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.expiryDate = valueDes;
          break;
        case r'days_left':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.daysLeft = valueDes;
          break;
        case r'last_reminded_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastRemindedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DocumentExpiry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DocumentExpiryBuilder();
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

class DocumentExpiryDocumentTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'id_card')
  static const DocumentExpiryDocumentTypeEnum idCard = _$documentExpiryDocumentTypeEnum_idCard;
  @BuiltValueEnumConst(wireName: r'security_license')
  static const DocumentExpiryDocumentTypeEnum securityLicense = _$documentExpiryDocumentTypeEnum_securityLicense;
  @BuiltValueEnumConst(wireName: r'training_cert')
  static const DocumentExpiryDocumentTypeEnum trainingCert = _$documentExpiryDocumentTypeEnum_trainingCert;
  @BuiltValueEnumConst(wireName: r'criminal_check')
  static const DocumentExpiryDocumentTypeEnum criminalCheck = _$documentExpiryDocumentTypeEnum_criminalCheck;
  @BuiltValueEnumConst(wireName: r'driver_license')
  static const DocumentExpiryDocumentTypeEnum driverLicense = _$documentExpiryDocumentTypeEnum_driverLicense;

  static Serializer<DocumentExpiryDocumentTypeEnum> get serializer => _$documentExpiryDocumentTypeEnumSerializer;

  const DocumentExpiryDocumentTypeEnum._(String name): super(name);

  static BuiltSet<DocumentExpiryDocumentTypeEnum> get values => _$documentExpiryDocumentTypeEnumValues;
  static DocumentExpiryDocumentTypeEnum valueOf(String name) => _$documentExpiryDocumentTypeEnumValueOf(name);
}

