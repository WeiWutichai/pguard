//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'org_settings.g.dart';

/// The org (company) profile shown on receipts + in-app. These three fields are the SELLER block a Thai full tax invoice (ใบกำกับภาษีแบบเต็มรูป) must carry: issuer name, TIN and registered address. Every field is nullable: an all-null object (incl. `updated_at`) is the \"never saved yet\" state returned by GET — and any receipt issued in that state is missing its legally-required issuer block. 
///
/// Properties:
/// * [companyName] - Issuer's legal name on the tax invoice; null = never filled in.
/// * [taxId] - Issuer's TIN (Thai: 13 digits); null = never filled in.
/// * [address] - Issuer's registered address; null = never filled in.
/// * [updatedAt] - When last saved; null until first written.
@BuiltValue()
abstract class OrgSettings implements Built<OrgSettings, OrgSettingsBuilder> {
  /// Issuer's legal name on the tax invoice; null = never filled in.
  @BuiltValueField(wireName: r'company_name')
  String? get companyName;

  /// Issuer's TIN (Thai: 13 digits); null = never filled in.
  @BuiltValueField(wireName: r'tax_id')
  String? get taxId;

  /// Issuer's registered address; null = never filled in.
  @BuiltValueField(wireName: r'address')
  String? get address;

  /// When last saved; null until first written.
  @BuiltValueField(wireName: r'updated_at')
  DateTime? get updatedAt;

  OrgSettings._();

  factory OrgSettings([void updates(OrgSettingsBuilder b)]) = _$OrgSettings;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrgSettingsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrgSettings> get serializer => _$OrgSettingsSerializer();
}

class _$OrgSettingsSerializer implements PrimitiveSerializer<OrgSettings> {
  @override
  final Iterable<Type> types = const [OrgSettings, _$OrgSettings];

  @override
  final String wireName = r'OrgSettings';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrgSettings object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.companyName != null) {
      yield r'company_name';
      yield serializers.serialize(
        object.companyName,
        specifiedType: const FullType(String),
      );
    }
    if (object.taxId != null) {
      yield r'tax_id';
      yield serializers.serialize(
        object.taxId,
        specifiedType: const FullType(String),
      );
    }
    if (object.address != null) {
      yield r'address';
      yield serializers.serialize(
        object.address,
        specifiedType: const FullType(String),
      );
    }
    if (object.updatedAt != null) {
      yield r'updated_at';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OrgSettings object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrgSettingsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'company_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.companyName = valueDes;
          break;
        case r'tax_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.taxId = valueDes;
          break;
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrgSettings deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrgSettingsBuilder();
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

