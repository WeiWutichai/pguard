//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_org_settings_request.g.dart';

/// The org (company) profile body for `PUT /admin/org-settings`. All fields optional (the admin saves incrementally). `tax_id` is validated leniently (8–20 digits, spaces/hyphens allowed — not a checksum); `company_name`/`address` are bounded to 500 chars. 
///
/// Properties:
/// * [companyName] 
/// * [taxId] - 8–20 digits (spaces/hyphens allowed); a Thai TIN is 13 digits.
/// * [address] 
@BuiltValue()
abstract class UpdateOrgSettingsRequest implements Built<UpdateOrgSettingsRequest, UpdateOrgSettingsRequestBuilder> {
  @BuiltValueField(wireName: r'company_name')
  String? get companyName;

  /// 8–20 digits (spaces/hyphens allowed); a Thai TIN is 13 digits.
  @BuiltValueField(wireName: r'tax_id')
  String? get taxId;

  @BuiltValueField(wireName: r'address')
  String? get address;

  UpdateOrgSettingsRequest._();

  factory UpdateOrgSettingsRequest([void updates(UpdateOrgSettingsRequestBuilder b)]) = _$UpdateOrgSettingsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateOrgSettingsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateOrgSettingsRequest> get serializer => _$UpdateOrgSettingsRequestSerializer();
}

class _$UpdateOrgSettingsRequestSerializer implements PrimitiveSerializer<UpdateOrgSettingsRequest> {
  @override
  final Iterable<Type> types = const [UpdateOrgSettingsRequest, _$UpdateOrgSettingsRequest];

  @override
  final String wireName = r'UpdateOrgSettingsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateOrgSettingsRequest object, {
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
    UpdateOrgSettingsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpdateOrgSettingsRequestBuilder result,
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
  UpdateOrgSettingsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateOrgSettingsRequestBuilder();
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

