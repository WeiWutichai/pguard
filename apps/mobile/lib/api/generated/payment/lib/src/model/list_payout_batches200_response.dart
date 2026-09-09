//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/payout_batch_list.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_payout_batches200_response.g.dart';

/// ListPayoutBatches200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListPayoutBatches200Response implements ApiResponseEnvelope, Built<ListPayoutBatches200Response, ListPayoutBatches200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  PayoutBatchList? get data;

  ListPayoutBatches200Response._();

  factory ListPayoutBatches200Response([void updates(ListPayoutBatches200ResponseBuilder b)]) = _$ListPayoutBatches200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListPayoutBatches200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListPayoutBatches200Response> get serializer => _$ListPayoutBatches200ResponseSerializer();
}

class _$ListPayoutBatches200ResponseSerializer implements PrimitiveSerializer<ListPayoutBatches200Response> {
  @override
  final Iterable<Type> types = const [ListPayoutBatches200Response, _$ListPayoutBatches200Response];

  @override
  final String wireName = r'ListPayoutBatches200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListPayoutBatches200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(PayoutBatchList),
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
    ListPayoutBatches200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListPayoutBatches200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PayoutBatchList),
          ) as PayoutBatchList;
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
  ListPayoutBatches200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListPayoutBatches200ResponseBuilder();
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

