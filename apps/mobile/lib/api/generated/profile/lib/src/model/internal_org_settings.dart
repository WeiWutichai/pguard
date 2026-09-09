//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'internal_org_settings.g.dart';

/// The company / WHT-payer block returned by `GET /internal/org-settings` (service-JWT). A slim mirror of `OrgSettings` WITHOUT `updated_at` (the payer block has no use for the bookkeeping timestamp). All-`null` is the legitimate \"never saved\" state, returned as 200 — not a 404. 
///
/// Properties:
/// * [companyName] - Legal payer name on the SCB file header + ภ.ง.ด.53; null blocks the export.
/// * [taxId] - The COMPANY (juristic-person) payer TIN. Shape-validated only — the citizen mod-11 checksum deliberately does not apply here (see `UpdateOrgSettingsRequest.tax_id`). `null` is what makes `POST /admin/payouts/export` refuse to produce a file. 
/// * [address] - Registered payer address for the ภ.ง.ด.53 header.
@BuiltValue()
abstract class InternalOrgSettings implements Built<InternalOrgSettings, InternalOrgSettingsBuilder> {
  /// Legal payer name on the SCB file header + ภ.ง.ด.53; null blocks the export.
  @BuiltValueField(wireName: r'company_name')
  String? get companyName;

  /// The COMPANY (juristic-person) payer TIN. Shape-validated only — the citizen mod-11 checksum deliberately does not apply here (see `UpdateOrgSettingsRequest.tax_id`). `null` is what makes `POST /admin/payouts/export` refuse to produce a file. 
  @BuiltValueField(wireName: r'tax_id')
  String? get taxId;

  /// Registered payer address for the ภ.ง.ด.53 header.
  @BuiltValueField(wireName: r'address')
  String? get address;

  InternalOrgSettings._();

  factory InternalOrgSettings([void updates(InternalOrgSettingsBuilder b)]) = _$InternalOrgSettings;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InternalOrgSettingsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InternalOrgSettings> get serializer => _$InternalOrgSettingsSerializer();
}

class _$InternalOrgSettingsSerializer implements PrimitiveSerializer<InternalOrgSettings> {
  @override
  final Iterable<Type> types = const [InternalOrgSettings, _$InternalOrgSettings];

  @override
  final String wireName = r'InternalOrgSettings';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InternalOrgSettings object, {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    InternalOrgSettings object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InternalOrgSettingsBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InternalOrgSettings deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InternalOrgSettingsBuilder();
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

