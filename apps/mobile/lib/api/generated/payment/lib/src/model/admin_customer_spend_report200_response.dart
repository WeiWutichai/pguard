//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/customer_spend.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_customer_spend_report200_response.g.dart';

/// AdminCustomerSpendReport200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminCustomerSpendReport200Response implements ApiResponseEnvelope, Built<AdminCustomerSpendReport200Response, AdminCustomerSpendReport200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<CustomerSpend>? get data;

  AdminCustomerSpendReport200Response._();

  factory AdminCustomerSpendReport200Response([void updates(AdminCustomerSpendReport200ResponseBuilder b)]) = _$AdminCustomerSpendReport200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminCustomerSpendReport200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminCustomerSpendReport200Response> get serializer => _$AdminCustomerSpendReport200ResponseSerializer();
}

class _$AdminCustomerSpendReport200ResponseSerializer implements PrimitiveSerializer<AdminCustomerSpendReport200Response> {
  @override
  final Iterable<Type> types = const [AdminCustomerSpendReport200Response, _$AdminCustomerSpendReport200Response];

  @override
  final String wireName = r'AdminCustomerSpendReport200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminCustomerSpendReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(CustomerSpend)]),
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
    AdminCustomerSpendReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminCustomerSpendReport200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CustomerSpend)]),
          ) as BuiltList<CustomerSpend>;
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
  AdminCustomerSpendReport200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminCustomerSpendReport200ResponseBuilder();
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

