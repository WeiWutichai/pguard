//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_identity_api/src/model/change_password200_response_all_of_data.dart';
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'change_password200_response.g.dart';

/// ChangePassword200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ChangePassword200Response implements ApiResponseEnvelope, Built<ChangePassword200Response, ChangePassword200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  ChangePassword200ResponseAllOfData? get data;

  ChangePassword200Response._();

  factory ChangePassword200Response([void updates(ChangePassword200ResponseBuilder b)]) = _$ChangePassword200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ChangePassword200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ChangePassword200Response> get serializer => _$ChangePassword200ResponseSerializer();
}

class _$ChangePassword200ResponseSerializer implements PrimitiveSerializer<ChangePassword200Response> {
  @override
  final Iterable<Type> types = const [ChangePassword200Response, _$ChangePassword200Response];

  @override
  final String wireName = r'ChangePassword200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ChangePassword200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(ChangePassword200ResponseAllOfData),
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
    ChangePassword200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ChangePassword200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ChangePassword200ResponseAllOfData),
          ) as ChangePassword200ResponseAllOfData;
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
  ChangePassword200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ChangePassword200ResponseBuilder();
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

