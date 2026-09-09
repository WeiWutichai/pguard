//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'void_payout_batch_items_request.g.dart';

/// VoidPayoutBatchItemsRequest
///
/// Properties:
/// * [bookingIds] - The bookings whose credit lines the bank could not deliver. Every one must belong to THIS batch (else 404) and still be live (else 409); duplicates are collapsed. An empty list is a 400 — it must never be read as \"all of them\", which is the whole-batch void. 
/// * [reason] - Why these lines are going back in the queue (e.g. the bank's rejection message). Non-blank.
@BuiltValue()
abstract class VoidPayoutBatchItemsRequest implements Built<VoidPayoutBatchItemsRequest, VoidPayoutBatchItemsRequestBuilder> {
  /// The bookings whose credit lines the bank could not deliver. Every one must belong to THIS batch (else 404) and still be live (else 409); duplicates are collapsed. An empty list is a 400 — it must never be read as \"all of them\", which is the whole-batch void. 
  @BuiltValueField(wireName: r'booking_ids')
  BuiltList<String> get bookingIds;

  /// Why these lines are going back in the queue (e.g. the bank's rejection message). Non-blank.
  @BuiltValueField(wireName: r'reason')
  String get reason;

  VoidPayoutBatchItemsRequest._();

  factory VoidPayoutBatchItemsRequest([void updates(VoidPayoutBatchItemsRequestBuilder b)]) = _$VoidPayoutBatchItemsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VoidPayoutBatchItemsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VoidPayoutBatchItemsRequest> get serializer => _$VoidPayoutBatchItemsRequestSerializer();
}

class _$VoidPayoutBatchItemsRequestSerializer implements PrimitiveSerializer<VoidPayoutBatchItemsRequest> {
  @override
  final Iterable<Type> types = const [VoidPayoutBatchItemsRequest, _$VoidPayoutBatchItemsRequest];

  @override
  final String wireName = r'VoidPayoutBatchItemsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VoidPayoutBatchItemsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'booking_ids';
    yield serializers.serialize(
      object.bookingIds,
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
    VoidPayoutBatchItemsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VoidPayoutBatchItemsRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'booking_ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.bookingIds.replace(valueDes);
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
  VoidPayoutBatchItemsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VoidPayoutBatchItemsRequestBuilder();
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

