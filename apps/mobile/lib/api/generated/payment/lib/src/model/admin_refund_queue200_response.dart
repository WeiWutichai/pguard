//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/refund_queue_response.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_refund_queue200_response.g.dart';

/// AdminRefundQueue200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminRefundQueue200Response implements ApiResponseEnvelope, Built<AdminRefundQueue200Response, AdminRefundQueue200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  RefundQueueResponse? get data;

  AdminRefundQueue200Response._();

  factory AdminRefundQueue200Response([void updates(AdminRefundQueue200ResponseBuilder b)]) = _$AdminRefundQueue200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminRefundQueue200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminRefundQueue200Response> get serializer => _$AdminRefundQueue200ResponseSerializer();
}

class _$AdminRefundQueue200ResponseSerializer implements PrimitiveSerializer<AdminRefundQueue200Response> {
  @override
  final Iterable<Type> types = const [AdminRefundQueue200Response, _$AdminRefundQueue200Response];

  @override
  final String wireName = r'AdminRefundQueue200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminRefundQueue200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(RefundQueueResponse),
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
    AdminRefundQueue200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminRefundQueue200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RefundQueueResponse),
          ) as RefundQueueResponse;
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
  AdminRefundQueue200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminRefundQueue200ResponseBuilder();
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

