//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_booking_api/src/model/api_response_envelope.dart';
import 'package:pguard_booking_api/src/model/booking.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_bookings200_response.g.dart';

/// ListBookings200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListBookings200Response implements ApiResponseEnvelope, Built<ListBookings200Response, ListBookings200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<Booking>? get data;

  ListBookings200Response._();

  factory ListBookings200Response([void updates(ListBookings200ResponseBuilder b)]) = _$ListBookings200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListBookings200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListBookings200Response> get serializer => _$ListBookings200ResponseSerializer();
}

class _$ListBookings200ResponseSerializer implements PrimitiveSerializer<ListBookings200Response> {
  @override
  final Iterable<Type> types = const [ListBookings200Response, _$ListBookings200Response];

  @override
  final String wireName = r'ListBookings200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListBookings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(Booking)]),
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
    ListBookings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListBookings200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Booking)]),
          ) as BuiltList<Booking>;
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
  ListBookings200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListBookings200ResponseBuilder();
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

