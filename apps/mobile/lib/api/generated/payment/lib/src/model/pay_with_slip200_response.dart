//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/payment.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pay_with_slip200_response.g.dart';

/// PayWithSlip200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class PayWithSlip200Response implements ApiResponseEnvelope, Built<PayWithSlip200Response, PayWithSlip200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  Payment? get data;

  PayWithSlip200Response._();

  factory PayWithSlip200Response([void updates(PayWithSlip200ResponseBuilder b)]) = _$PayWithSlip200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PayWithSlip200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PayWithSlip200Response> get serializer => _$PayWithSlip200ResponseSerializer();
}

class _$PayWithSlip200ResponseSerializer implements PrimitiveSerializer<PayWithSlip200Response> {
  @override
  final Iterable<Type> types = const [PayWithSlip200Response, _$PayWithSlip200Response];

  @override
  final String wireName = r'PayWithSlip200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PayWithSlip200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(Payment),
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
    PayWithSlip200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PayWithSlip200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Payment),
          ) as Payment;
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
  PayWithSlip200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PayWithSlip200ResponseBuilder();
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

