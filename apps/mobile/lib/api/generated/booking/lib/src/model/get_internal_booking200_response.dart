//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_booking_api/src/model/internal_booking.dart';
import 'package:pguard_booking_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_internal_booking200_response.g.dart';

/// GetInternalBooking200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetInternalBooking200Response implements ApiResponseEnvelope, Built<GetInternalBooking200Response, GetInternalBooking200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  InternalBooking? get data;

  GetInternalBooking200Response._();

  factory GetInternalBooking200Response([void updates(GetInternalBooking200ResponseBuilder b)]) = _$GetInternalBooking200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetInternalBooking200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetInternalBooking200Response> get serializer => _$GetInternalBooking200ResponseSerializer();
}

class _$GetInternalBooking200ResponseSerializer implements PrimitiveSerializer<GetInternalBooking200Response> {
  @override
  final Iterable<Type> types = const [GetInternalBooking200Response, _$GetInternalBooking200Response];

  @override
  final String wireName = r'GetInternalBooking200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetInternalBooking200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(InternalBooking),
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
    GetInternalBooking200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetInternalBooking200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(InternalBooking),
          ) as InternalBooking;
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
  GetInternalBooking200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetInternalBooking200ResponseBuilder();
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

