//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/date.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'document_expiry_input.g.dart';

/// One document's expiry date, folded into the guard-profile submit (the registration doc step). Metadata only — no image. The passbook is NOT an expiring credential and is excluded. An unknown type or a non-future date is skipped server-side (best-effort). 
///
/// Properties:
/// * [documentType] 
/// * [expiryDate] - Must be in the future (a renewal date).
@BuiltValue()
abstract class DocumentExpiryInput implements Built<DocumentExpiryInput, DocumentExpiryInputBuilder> {
  @BuiltValueField(wireName: r'document_type')
  DocumentExpiryInputDocumentTypeEnum get documentType;
  // enum documentTypeEnum {  id_card,  security_license,  training_cert,  criminal_check,  driver_license,  };

  /// Must be in the future (a renewal date).
  @BuiltValueField(wireName: r'expiry_date')
  Date get expiryDate;

  DocumentExpiryInput._();

  factory DocumentExpiryInput([void updates(DocumentExpiryInputBuilder b)]) = _$DocumentExpiryInput;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DocumentExpiryInputBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DocumentExpiryInput> get serializer => _$DocumentExpiryInputSerializer();
}

class _$DocumentExpiryInputSerializer implements PrimitiveSerializer<DocumentExpiryInput> {
  @override
  final Iterable<Type> types = const [DocumentExpiryInput, _$DocumentExpiryInput];

  @override
  final String wireName = r'DocumentExpiryInput';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DocumentExpiryInput object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'document_type';
    yield serializers.serialize(
      object.documentType,
      specifiedType: const FullType(DocumentExpiryInputDocumentTypeEnum),
    );
    yield r'expiry_date';
    yield serializers.serialize(
      object.expiryDate,
      specifiedType: const FullType(Date),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DocumentExpiryInput object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DocumentExpiryInputBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'document_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DocumentExpiryInputDocumentTypeEnum),
          ) as DocumentExpiryInputDocumentTypeEnum;
          result.documentType = valueDes;
          break;
        case r'expiry_date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.expiryDate = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DocumentExpiryInput deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DocumentExpiryInputBuilder();
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

class DocumentExpiryInputDocumentTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'id_card')
  static const DocumentExpiryInputDocumentTypeEnum idCard = _$documentExpiryInputDocumentTypeEnum_idCard;
  @BuiltValueEnumConst(wireName: r'security_license')
  static const DocumentExpiryInputDocumentTypeEnum securityLicense = _$documentExpiryInputDocumentTypeEnum_securityLicense;
  @BuiltValueEnumConst(wireName: r'training_cert')
  static const DocumentExpiryInputDocumentTypeEnum trainingCert = _$documentExpiryInputDocumentTypeEnum_trainingCert;
  @BuiltValueEnumConst(wireName: r'criminal_check')
  static const DocumentExpiryInputDocumentTypeEnum criminalCheck = _$documentExpiryInputDocumentTypeEnum_criminalCheck;
  @BuiltValueEnumConst(wireName: r'driver_license')
  static const DocumentExpiryInputDocumentTypeEnum driverLicense = _$documentExpiryInputDocumentTypeEnum_driverLicense;

  static Serializer<DocumentExpiryInputDocumentTypeEnum> get serializer => _$documentExpiryInputDocumentTypeEnumSerializer;

  const DocumentExpiryInputDocumentTypeEnum._(String name): super(name);

  static BuiltSet<DocumentExpiryInputDocumentTypeEnum> get values => _$documentExpiryInputDocumentTypeEnumValues;
  static DocumentExpiryInputDocumentTypeEnum valueOf(String name) => _$documentExpiryInputDocumentTypeEnumValueOf(name);
}

