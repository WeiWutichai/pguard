//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_booking_api/src/model/customer_booking_stat.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_booking_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_customer_bookings_report200_response.g.dart';

/// AdminCustomerBookingsReport200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminCustomerBookingsReport200Response implements ApiResponseEnvelope, Built<AdminCustomerBookingsReport200Response, AdminCustomerBookingsReport200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<CustomerBookingStat>? get data;

  AdminCustomerBookingsReport200Response._();

  factory AdminCustomerBookingsReport200Response([void updates(AdminCustomerBookingsReport200ResponseBuilder b)]) = _$AdminCustomerBookingsReport200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminCustomerBookingsReport200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminCustomerBookingsReport200Response> get serializer => _$AdminCustomerBookingsReport200ResponseSerializer();
}

class _$AdminCustomerBookingsReport200ResponseSerializer implements PrimitiveSerializer<AdminCustomerBookingsReport200Response> {
  @override
  final Iterable<Type> types = const [AdminCustomerBookingsReport200Response, _$AdminCustomerBookingsReport200Response];

  @override
  final String wireName = r'AdminCustomerBookingsReport200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminCustomerBookingsReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(CustomerBookingStat)]),
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
    AdminCustomerBookingsReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminCustomerBookingsReport200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CustomerBookingStat)]),
          ) as BuiltList<CustomerBookingStat>;
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
  AdminCustomerBookingsReport200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminCustomerBookingsReport200ResponseBuilder();
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

