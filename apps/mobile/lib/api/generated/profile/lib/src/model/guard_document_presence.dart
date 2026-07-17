//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_document_presence.g.dart';

/// Per-credential PRESENCE (has / doesn''t-have) for the five customer-relevant credential documents. Booleans ONLY — a `true` means the document is on record; the file bytes never cross the wire (they stay owner/admin-only). Passbook is excluded (banking, not a credential). 
///
/// Properties:
/// * [idCard] 
/// * [securityLicense] 
/// * [trainingCert] 
/// * [criminalCheck] 
/// * [driverLicense] 
@BuiltValue()
abstract class GuardDocumentPresence implements Built<GuardDocumentPresence, GuardDocumentPresenceBuilder> {
  @BuiltValueField(wireName: r'id_card')
  bool get idCard;

  @BuiltValueField(wireName: r'security_license')
  bool get securityLicense;

  @BuiltValueField(wireName: r'training_cert')
  bool get trainingCert;

  @BuiltValueField(wireName: r'criminal_check')
  bool get criminalCheck;

  @BuiltValueField(wireName: r'driver_license')
  bool get driverLicense;

  GuardDocumentPresence._();

  factory GuardDocumentPresence([void updates(GuardDocumentPresenceBuilder b)]) = _$GuardDocumentPresence;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuardDocumentPresenceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardDocumentPresence> get serializer => _$GuardDocumentPresenceSerializer();
}

class _$GuardDocumentPresenceSerializer implements PrimitiveSerializer<GuardDocumentPresence> {
  @override
  final Iterable<Type> types = const [GuardDocumentPresence, _$GuardDocumentPresence];

  @override
  final String wireName = r'GuardDocumentPresence';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardDocumentPresence object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id_card';
    yield serializers.serialize(
      object.idCard,
      specifiedType: const FullType(bool),
    );
    yield r'security_license';
    yield serializers.serialize(
      object.securityLicense,
      specifiedType: const FullType(bool),
    );
    yield r'training_cert';
    yield serializers.serialize(
      object.trainingCert,
      specifiedType: const FullType(bool),
    );
    yield r'criminal_check';
    yield serializers.serialize(
      object.criminalCheck,
      specifiedType: const FullType(bool),
    );
    yield r'driver_license';
    yield serializers.serialize(
      object.driverLicense,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuardDocumentPresence object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardDocumentPresenceBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id_card':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.idCard = valueDes;
          break;
        case r'security_license':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.securityLicense = valueDes;
          break;
        case r'training_cert':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.trainingCert = valueDes;
          break;
        case r'criminal_check':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.criminalCheck = valueDes;
          break;
        case r'driver_license':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.driverLicense = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuardDocumentPresence deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuardDocumentPresenceBuilder();
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

