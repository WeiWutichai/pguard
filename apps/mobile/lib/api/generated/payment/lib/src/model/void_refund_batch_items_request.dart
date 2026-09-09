//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/refund_source_ref.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'void_refund_batch_items_request.g.dart';

/// VoidRefundBatchItemsRequest
///
/// Properties:
/// * [sources] - The obligations whose credit lines the bank could not deliver. Every one must belong to THIS batch (else 404) and still be live (else 409); exact duplicates are collapsed. An empty list is a 400 — it must never be read as \"all of them\", which is the whole-batch void. 
/// * [reason] - Why these obligations are going back in the queue (e.g. the bank's rejection message). Non-blank.
@BuiltValue()
abstract class VoidRefundBatchItemsRequest implements Built<VoidRefundBatchItemsRequest, VoidRefundBatchItemsRequestBuilder> {
  /// The obligations whose credit lines the bank could not deliver. Every one must belong to THIS batch (else 404) and still be live (else 409); exact duplicates are collapsed. An empty list is a 400 — it must never be read as \"all of them\", which is the whole-batch void. 
  @BuiltValueField(wireName: r'sources')
  BuiltList<RefundSourceRef> get sources;

  /// Why these obligations are going back in the queue (e.g. the bank's rejection message). Non-blank.
  @BuiltValueField(wireName: r'reason')
  String get reason;

  VoidRefundBatchItemsRequest._();

  factory VoidRefundBatchItemsRequest([void updates(VoidRefundBatchItemsRequestBuilder b)]) = _$VoidRefundBatchItemsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VoidRefundBatchItemsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VoidRefundBatchItemsRequest> get serializer => _$VoidRefundBatchItemsRequestSerializer();
}

class _$VoidRefundBatchItemsRequestSerializer implements PrimitiveSerializer<VoidRefundBatchItemsRequest> {
  @override
  final Iterable<Type> types = const [VoidRefundBatchItemsRequest, _$VoidRefundBatchItemsRequest];

  @override
  final String wireName = r'VoidRefundBatchItemsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VoidRefundBatchItemsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sources';
    yield serializers.serialize(
      object.sources,
      specifiedType: const FullType(BuiltList, [FullType(RefundSourceRef)]),
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
    VoidRefundBatchItemsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VoidRefundBatchItemsRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sources':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RefundSourceRef)]),
          ) as BuiltList<RefundSourceRef>;
          result.sources.replace(valueDes);
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
  VoidRefundBatchItemsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VoidRefundBatchItemsRequestBuilder();
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

