//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/refund_batch_list.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_refund_batches200_response.g.dart';

/// ListRefundBatches200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListRefundBatches200Response implements ApiResponseEnvelope, Built<ListRefundBatches200Response, ListRefundBatches200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  RefundBatchList? get data;

  ListRefundBatches200Response._();

  factory ListRefundBatches200Response([void updates(ListRefundBatches200ResponseBuilder b)]) = _$ListRefundBatches200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListRefundBatches200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListRefundBatches200Response> get serializer => _$ListRefundBatches200ResponseSerializer();
}

class _$ListRefundBatches200ResponseSerializer implements PrimitiveSerializer<ListRefundBatches200Response> {
  @override
  final Iterable<Type> types = const [ListRefundBatches200Response, _$ListRefundBatches200Response];

  @override
  final String wireName = r'ListRefundBatches200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListRefundBatches200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(RefundBatchList),
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
    ListRefundBatches200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListRefundBatches200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RefundBatchList),
          ) as RefundBatchList;
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
  ListRefundBatches200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListRefundBatches200ResponseBuilder();
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

