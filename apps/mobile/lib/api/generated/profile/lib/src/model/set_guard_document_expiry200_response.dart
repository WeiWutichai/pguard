//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/guard_document_expiry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_guard_document_expiry200_response.g.dart';

/// SetGuardDocumentExpiry200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class SetGuardDocumentExpiry200Response implements ApiResponseEnvelope, Built<SetGuardDocumentExpiry200Response, SetGuardDocumentExpiry200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  GuardDocumentExpiry? get data;

  SetGuardDocumentExpiry200Response._();

  factory SetGuardDocumentExpiry200Response([void updates(SetGuardDocumentExpiry200ResponseBuilder b)]) = _$SetGuardDocumentExpiry200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetGuardDocumentExpiry200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetGuardDocumentExpiry200Response> get serializer => _$SetGuardDocumentExpiry200ResponseSerializer();
}

class _$SetGuardDocumentExpiry200ResponseSerializer implements PrimitiveSerializer<SetGuardDocumentExpiry200Response> {
  @override
  final Iterable<Type> types = const [SetGuardDocumentExpiry200Response, _$SetGuardDocumentExpiry200Response];

  @override
  final String wireName = r'SetGuardDocumentExpiry200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetGuardDocumentExpiry200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(GuardDocumentExpiry),
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
    SetGuardDocumentExpiry200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetGuardDocumentExpiry200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(GuardDocumentExpiry),
          ) as GuardDocumentExpiry;
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
  SetGuardDocumentExpiry200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetGuardDocumentExpiry200ResponseBuilder();
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

