//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/payout_batch_detail.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'get_payout_batch200_response.g.dart';

/// GetPayoutBatch200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class GetPayoutBatch200Response implements ApiResponseEnvelope, Built<GetPayoutBatch200Response, GetPayoutBatch200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  PayoutBatchDetail? get data;

  GetPayoutBatch200Response._();

  factory GetPayoutBatch200Response([void updates(GetPayoutBatch200ResponseBuilder b)]) = _$GetPayoutBatch200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetPayoutBatch200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetPayoutBatch200Response> get serializer => _$GetPayoutBatch200ResponseSerializer();
}

class _$GetPayoutBatch200ResponseSerializer implements PrimitiveSerializer<GetPayoutBatch200Response> {
  @override
  final Iterable<Type> types = const [GetPayoutBatch200Response, _$GetPayoutBatch200Response];

  @override
  final String wireName = r'GetPayoutBatch200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetPayoutBatch200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(PayoutBatchDetail),
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
    GetPayoutBatch200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GetPayoutBatch200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PayoutBatchDetail),
          ) as PayoutBatchDetail;
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
  GetPayoutBatch200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetPayoutBatch200ResponseBuilder();
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

