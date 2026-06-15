//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_booking_api/src/model/api_response_envelope.dart';
import 'package:pguard_booking_api/src/model/bookings_report.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_bookings_report200_response.g.dart';

/// AdminBookingsReport200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminBookingsReport200Response implements ApiResponseEnvelope, Built<AdminBookingsReport200Response, AdminBookingsReport200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BookingsReport? get data;

  AdminBookingsReport200Response._();

  factory AdminBookingsReport200Response([void updates(AdminBookingsReport200ResponseBuilder b)]) = _$AdminBookingsReport200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminBookingsReport200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminBookingsReport200Response> get serializer => _$AdminBookingsReport200ResponseSerializer();
}

class _$AdminBookingsReport200ResponseSerializer implements PrimitiveSerializer<AdminBookingsReport200Response> {
  @override
  final Iterable<Type> types = const [AdminBookingsReport200Response, _$AdminBookingsReport200Response];

  @override
  final String wireName = r'AdminBookingsReport200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminBookingsReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BookingsReport),
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
    AdminBookingsReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminBookingsReport200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BookingsReport),
          ) as BookingsReport;
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
  AdminBookingsReport200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminBookingsReport200ResponseBuilder();
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

