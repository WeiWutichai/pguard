//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_booking_api/src/model/skip_booking200_response_all_of_data.dart';
import 'package:pguard_booking_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'skip_booking200_response.g.dart';

/// SkipBooking200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class SkipBooking200Response implements ApiResponseEnvelope, Built<SkipBooking200Response, SkipBooking200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  SkipBooking200ResponseAllOfData? get data;

  SkipBooking200Response._();

  factory SkipBooking200Response([void updates(SkipBooking200ResponseBuilder b)]) = _$SkipBooking200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SkipBooking200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SkipBooking200Response> get serializer => _$SkipBooking200ResponseSerializer();
}

class _$SkipBooking200ResponseSerializer implements PrimitiveSerializer<SkipBooking200Response> {
  @override
  final Iterable<Type> types = const [SkipBooking200Response, _$SkipBooking200Response];

  @override
  final String wireName = r'SkipBooking200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SkipBooking200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(SkipBooking200ResponseAllOfData),
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
    SkipBooking200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SkipBooking200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SkipBooking200ResponseAllOfData),
          ) as SkipBooking200ResponseAllOfData;
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
  SkipBooking200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SkipBooking200ResponseBuilder();
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

