//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/vat_register_report.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'vat_register_report200_response.g.dart';

/// VatRegisterReport200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class VatRegisterReport200Response implements ApiResponseEnvelope, Built<VatRegisterReport200Response, VatRegisterReport200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  VatRegisterReport? get data;

  VatRegisterReport200Response._();

  factory VatRegisterReport200Response([void updates(VatRegisterReport200ResponseBuilder b)]) = _$VatRegisterReport200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VatRegisterReport200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VatRegisterReport200Response> get serializer => _$VatRegisterReport200ResponseSerializer();
}

class _$VatRegisterReport200ResponseSerializer implements PrimitiveSerializer<VatRegisterReport200Response> {
  @override
  final Iterable<Type> types = const [VatRegisterReport200Response, _$VatRegisterReport200Response];

  @override
  final String wireName = r'VatRegisterReport200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VatRegisterReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(VatRegisterReport),
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
    VatRegisterReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VatRegisterReport200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(VatRegisterReport),
          ) as VatRegisterReport;
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
  VatRegisterReport200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VatRegisterReport200ResponseBuilder();
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

