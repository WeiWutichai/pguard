//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/internal_org_settings.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'internal_org_settings200_response.g.dart';

/// InternalOrgSettings200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class InternalOrgSettings200Response implements ApiResponseEnvelope, Built<InternalOrgSettings200Response, InternalOrgSettings200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  InternalOrgSettings? get data;

  InternalOrgSettings200Response._();

  factory InternalOrgSettings200Response([void updates(InternalOrgSettings200ResponseBuilder b)]) = _$InternalOrgSettings200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InternalOrgSettings200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InternalOrgSettings200Response> get serializer => _$InternalOrgSettings200ResponseSerializer();
}

class _$InternalOrgSettings200ResponseSerializer implements PrimitiveSerializer<InternalOrgSettings200Response> {
  @override
  final Iterable<Type> types = const [InternalOrgSettings200Response, _$InternalOrgSettings200Response];

  @override
  final String wireName = r'InternalOrgSettings200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InternalOrgSettings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(InternalOrgSettings),
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
    InternalOrgSettings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InternalOrgSettings200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(InternalOrgSettings),
          ) as InternalOrgSettings;
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
  InternalOrgSettings200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InternalOrgSettings200ResponseBuilder();
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

