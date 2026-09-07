//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/deduction_batch_list.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_deduction_batches200_response.g.dart';

/// ListDeductionBatches200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListDeductionBatches200Response implements ApiResponseEnvelope, Built<ListDeductionBatches200Response, ListDeductionBatches200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  DeductionBatchList? get data;

  ListDeductionBatches200Response._();

  factory ListDeductionBatches200Response([void updates(ListDeductionBatches200ResponseBuilder b)]) = _$ListDeductionBatches200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListDeductionBatches200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListDeductionBatches200Response> get serializer => _$ListDeductionBatches200ResponseSerializer();
}

class _$ListDeductionBatches200ResponseSerializer implements PrimitiveSerializer<ListDeductionBatches200Response> {
  @override
  final Iterable<Type> types = const [ListDeductionBatches200Response, _$ListDeductionBatches200Response];

  @override
  final String wireName = r'ListDeductionBatches200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListDeductionBatches200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(DeductionBatchList),
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
    ListDeductionBatches200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListDeductionBatches200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DeductionBatchList),
          ) as DeductionBatchList;
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
  ListDeductionBatches200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListDeductionBatches200ResponseBuilder();
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

