//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/org_settings.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_get_org_settings200_response.g.dart';

/// AdminGetOrgSettings200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminGetOrgSettings200Response implements ApiResponseEnvelope, Built<AdminGetOrgSettings200Response, AdminGetOrgSettings200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  OrgSettings? get data;

  AdminGetOrgSettings200Response._();

  factory AdminGetOrgSettings200Response([void updates(AdminGetOrgSettings200ResponseBuilder b)]) = _$AdminGetOrgSettings200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminGetOrgSettings200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminGetOrgSettings200Response> get serializer => _$AdminGetOrgSettings200ResponseSerializer();
}

class _$AdminGetOrgSettings200ResponseSerializer implements PrimitiveSerializer<AdminGetOrgSettings200Response> {
  @override
  final Iterable<Type> types = const [AdminGetOrgSettings200Response, _$AdminGetOrgSettings200Response];

  @override
  final String wireName = r'AdminGetOrgSettings200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminGetOrgSettings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(OrgSettings),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
    yield r'success';
    yield serializers.serialize(
      object.success,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminGetOrgSettings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminGetOrgSettings200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(OrgSettings),
          ) as OrgSettings;
          result.data.replace(valueDes);
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminGetOrgSettings200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminGetOrgSettings200ResponseBuilder();
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

