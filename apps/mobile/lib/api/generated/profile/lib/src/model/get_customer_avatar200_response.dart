//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/customer_avatar_response.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_customer_avatar200_response.g.dart';

/// GetCustomerAvatar200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetCustomerAvatar200Response implements ApiResponseEnvelope, Built<GetCustomerAvatar200Response, GetCustomerAvatar200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  CustomerAvatarResponse? get data;

  GetCustomerAvatar200Response._();

  factory GetCustomerAvatar200Response([void updates(GetCustomerAvatar200ResponseBuilder b)]) = _$GetCustomerAvatar200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetCustomerAvatar200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetCustomerAvatar200Response> get serializer => _$GetCustomerAvatar200ResponseSerializer();
}

class _$GetCustomerAvatar200ResponseSerializer implements PrimitiveSerializer<GetCustomerAvatar200Response> {
  @override
  final Iterable<Type> types = const [GetCustomerAvatar200Response, _$GetCustomerAvatar200Response];

  @override
  final String wireName = r'GetCustomerAvatar200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetCustomerAvatar200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(CustomerAvatarResponse),
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
    GetCustomerAvatar200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetCustomerAvatar200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CustomerAvatarResponse),
          ) as CustomerAvatarResponse;
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
  GetCustomerAvatar200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetCustomerAvatar200ResponseBuilder();
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

