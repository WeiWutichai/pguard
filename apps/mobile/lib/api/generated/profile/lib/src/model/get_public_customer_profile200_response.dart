//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/public_customer_profile.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_public_customer_profile200_response.g.dart';

/// GetPublicCustomerProfile200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetPublicCustomerProfile200Response implements ApiResponseEnvelope, Built<GetPublicCustomerProfile200Response, GetPublicCustomerProfile200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  PublicCustomerProfile? get data;

  GetPublicCustomerProfile200Response._();

  factory GetPublicCustomerProfile200Response([void updates(GetPublicCustomerProfile200ResponseBuilder b)]) = _$GetPublicCustomerProfile200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetPublicCustomerProfile200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetPublicCustomerProfile200Response> get serializer => _$GetPublicCustomerProfile200ResponseSerializer();
}

class _$GetPublicCustomerProfile200ResponseSerializer implements PrimitiveSerializer<GetPublicCustomerProfile200Response> {
  @override
  final Iterable<Type> types = const [GetPublicCustomerProfile200Response, _$GetPublicCustomerProfile200Response];

  @override
  final String wireName = r'GetPublicCustomerProfile200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetPublicCustomerProfile200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(PublicCustomerProfile),
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
    GetPublicCustomerProfile200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetPublicCustomerProfile200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PublicCustomerProfile),
          ) as PublicCustomerProfile;
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
  GetPublicCustomerProfile200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetPublicCustomerProfile200ResponseBuilder();
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

