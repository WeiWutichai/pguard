//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/guard_document_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_guard_document200_response.g.dart';

/// GetGuardDocument200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetGuardDocument200Response implements ApiResponseEnvelope, Built<GetGuardDocument200Response, GetGuardDocument200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  GuardDocumentResponse? get data;

  GetGuardDocument200Response._();

  factory GetGuardDocument200Response([void updates(GetGuardDocument200ResponseBuilder b)]) = _$GetGuardDocument200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetGuardDocument200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetGuardDocument200Response> get serializer => _$GetGuardDocument200ResponseSerializer();
}

class _$GetGuardDocument200ResponseSerializer implements PrimitiveSerializer<GetGuardDocument200Response> {
  @override
  final Iterable<Type> types = const [GetGuardDocument200Response, _$GetGuardDocument200Response];

  @override
  final String wireName = r'GetGuardDocument200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetGuardDocument200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(GuardDocumentResponse),
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
    GetGuardDocument200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetGuardDocument200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(GuardDocumentResponse),
          ) as GuardDocumentResponse;
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
  GetGuardDocument200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetGuardDocument200ResponseBuilder();
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

