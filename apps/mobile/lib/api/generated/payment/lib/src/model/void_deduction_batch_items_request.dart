//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'void_deduction_batch_items_request.g.dart';

/// VoidDeductionBatchItemsRequest
///
/// Properties:
/// * [paymentIds] - The jobs to release. Must be non-empty (an empty list is NOT \"all of them\" — that is the whole-batch void), and every one must belong to THIS batch and still be live.
/// * [reason] - REQUIRED and non-blank — the record of why money the ledger says was collected is going back in the queue. Max 500 characters.
@BuiltValue()
abstract class VoidDeductionBatchItemsRequest implements Built<VoidDeductionBatchItemsRequest, VoidDeductionBatchItemsRequestBuilder> {
  /// The jobs to release. Must be non-empty (an empty list is NOT \"all of them\" — that is the whole-batch void), and every one must belong to THIS batch and still be live.
  @BuiltValueField(wireName: r'payment_ids')
  BuiltList<String> get paymentIds;

  /// REQUIRED and non-blank — the record of why money the ledger says was collected is going back in the queue. Max 500 characters.
  @BuiltValueField(wireName: r'reason')
  String get reason;

  VoidDeductionBatchItemsRequest._();

  factory VoidDeductionBatchItemsRequest([void updates(VoidDeductionBatchItemsRequestBuilder b)]) = _$VoidDeductionBatchItemsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VoidDeductionBatchItemsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VoidDeductionBatchItemsRequest> get serializer => _$VoidDeductionBatchItemsRequestSerializer();
}

class _$VoidDeductionBatchItemsRequestSerializer implements PrimitiveSerializer<VoidDeductionBatchItemsRequest> {
  @override
  final Iterable<Type> types = const [VoidDeductionBatchItemsRequest, _$VoidDeductionBatchItemsRequest];

  @override
  final String wireName = r'VoidDeductionBatchItemsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VoidDeductionBatchItemsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'payment_ids';
    yield serializers.serialize(
      object.paymentIds,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    VoidDeductionBatchItemsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VoidDeductionBatchItemsRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'payment_ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.paymentIds.replace(valueDes);
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  VoidDeductionBatchItemsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VoidDeductionBatchItemsRequestBuilder();
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

