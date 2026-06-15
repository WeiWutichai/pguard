//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/revenue_report.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_revenue_report200_response.g.dart';

/// AdminRevenueReport200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminRevenueReport200Response implements ApiResponseEnvelope, Built<AdminRevenueReport200Response, AdminRevenueReport200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  RevenueReport? get data;

  AdminRevenueReport200Response._();

  factory AdminRevenueReport200Response([void updates(AdminRevenueReport200ResponseBuilder b)]) = _$AdminRevenueReport200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminRevenueReport200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminRevenueReport200Response> get serializer => _$AdminRevenueReport200ResponseSerializer();
}

class _$AdminRevenueReport200ResponseSerializer implements PrimitiveSerializer<AdminRevenueReport200Response> {
  @override
  final Iterable<Type> types = const [AdminRevenueReport200Response, _$AdminRevenueReport200Response];

  @override
  final String wireName = r'AdminRevenueReport200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminRevenueReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(RevenueReport),
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
    AdminRevenueReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminRevenueReport200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RevenueReport),
          ) as RevenueReport;
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
  AdminRevenueReport200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminRevenueReport200ResponseBuilder();
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

