//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_documents.g.dart';

/// Per-credential PRESENCE (has / doesn''t-have), passed through from profile so the customer sees WHICH credential TYPES the guard has on file — never the files themselves. Booleans only. Omitted (not an all-false object) when profile didn''t say (older profile during a mixed-version deploy). Passbook is excluded (banking). 
///
/// Properties:
/// * [idCard] 
/// * [securityLicense] 
/// * [trainingCert] 
/// * [criminalCheck] 
/// * [driverLicense] 
@BuiltValue()
abstract class GuardDocuments implements Built<GuardDocuments, GuardDocumentsBuilder> {
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

  GuardDocuments._();

  factory GuardDocuments([void updates(GuardDocumentsBuilder b)]) = _$GuardDocuments;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuardDocumentsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardDocuments> get serializer => _$GuardDocumentsSerializer();
}

class _$GuardDocumentsSerializer implements PrimitiveSerializer<GuardDocuments> {
  @override
  final Iterable<Type> types = const [GuardDocuments, _$GuardDocuments];

  @override
  final String wireName = r'GuardDocuments';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardDocuments object, {
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
    GuardDocuments object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardDocumentsBuilder result,
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
  GuardDocuments deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuardDocumentsBuilder();
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

