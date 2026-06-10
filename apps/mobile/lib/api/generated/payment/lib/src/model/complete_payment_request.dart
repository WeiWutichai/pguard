//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'complete_payment_request.g.dart';

/// CompletePaymentRequest
///
/// Properties:
/// * [actualSeconds] - Seconds the guard actually worked (clamped to [0, booked_hours]).
@BuiltValue()
abstract class CompletePaymentRequest implements Built<CompletePaymentRequest, CompletePaymentRequestBuilder> {
  /// Seconds the guard actually worked (clamped to [0, booked_hours]).
  @BuiltValueField(wireName: r'actual_seconds')
  int get actualSeconds;

  CompletePaymentRequest._();

  factory CompletePaymentRequest([void updates(CompletePaymentRequestBuilder b)]) = _$CompletePaymentRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CompletePaymentRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CompletePaymentRequest> get serializer => _$CompletePaymentRequestSerializer();
}

class _$CompletePaymentRequestSerializer implements PrimitiveSerializer<CompletePaymentRequest> {
  @override
  final Iterable<Type> types = const [CompletePaymentRequest, _$CompletePaymentRequest];

  @override
  final String wireName = r'CompletePaymentRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CompletePaymentRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'actual_seconds';
    yield serializers.serialize(
      object.actualSeconds,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CompletePaymentRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CompletePaymentRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'actual_seconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.actualSeconds = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CompletePaymentRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CompletePaymentRequestBuilder();
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

