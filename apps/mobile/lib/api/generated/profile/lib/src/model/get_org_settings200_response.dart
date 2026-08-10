//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/org_settings.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_org_settings200_response.g.dart';

/// GetOrgSettings200Response
///
/// Properties:
/// * [data] 
@BuiltValue()
abstract class GetOrgSettings200Response implements Built<GetOrgSettings200Response, GetOrgSettings200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  OrgSettings? get data;

  GetOrgSettings200Response._();

  factory GetOrgSettings200Response([void updates(GetOrgSettings200ResponseBuilder b)]) = _$GetOrgSettings200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetOrgSettings200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetOrgSettings200Response> get serializer => _$GetOrgSettings200ResponseSerializer();
}

class _$GetOrgSettings200ResponseSerializer implements PrimitiveSerializer<GetOrgSettings200Response> {
  @override
  final Iterable<Type> types = const [GetOrgSettings200Response, _$GetOrgSettings200Response];

  @override
  final String wireName = r'GetOrgSettings200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetOrgSettings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(OrgSettings),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GetOrgSettings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetOrgSettings200ResponseBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GetOrgSettings200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetOrgSettings200ResponseBuilder();
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

