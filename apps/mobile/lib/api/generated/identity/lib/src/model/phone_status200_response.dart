//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_identity_api/src/model/phone_status200_response_all_of_data.dart';
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'phone_status200_response.g.dart';

/// PhoneStatus200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class PhoneStatus200Response implements ApiResponseEnvelope, Built<PhoneStatus200Response, PhoneStatus200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  PhoneStatus200ResponseAllOfData? get data;

  PhoneStatus200Response._();

  factory PhoneStatus200Response([void updates(PhoneStatus200ResponseBuilder b)]) = _$PhoneStatus200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhoneStatus200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhoneStatus200Response> get serializer => _$PhoneStatus200ResponseSerializer();
}

class _$PhoneStatus200ResponseSerializer implements PrimitiveSerializer<PhoneStatus200Response> {
  @override
  final Iterable<Type> types = const [PhoneStatus200Response, _$PhoneStatus200Response];

  @override
  final String wireName = r'PhoneStatus200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhoneStatus200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(PhoneStatus200ResponseAllOfData),
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
    PhoneStatus200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PhoneStatus200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PhoneStatus200ResponseAllOfData),
          ) as PhoneStatus200ResponseAllOfData;
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
  PhoneStatus200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhoneStatus200ResponseBuilder();
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

