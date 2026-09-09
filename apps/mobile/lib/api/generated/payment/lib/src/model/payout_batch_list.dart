//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/payout_batch.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'payout_batch_list.g.dart';

/// PayoutBatchList
///
/// Properties:
/// * [batches] 
/// * [total] - Total batches matching
@BuiltValue()
abstract class PayoutBatchList implements Built<PayoutBatchList, PayoutBatchListBuilder> {
  @BuiltValueField(wireName: r'batches')
  BuiltList<PayoutBatch> get batches;

  /// Total batches matching
  @BuiltValueField(wireName: r'total')
  int get total;

  PayoutBatchList._();

  factory PayoutBatchList([void updates(PayoutBatchListBuilder b)]) = _$PayoutBatchList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PayoutBatchListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PayoutBatchList> get serializer => _$PayoutBatchListSerializer();
}

class _$PayoutBatchListSerializer implements PrimitiveSerializer<PayoutBatchList> {
  @override
  final Iterable<Type> types = const [PayoutBatchList, _$PayoutBatchList];

  @override
  final String wireName = r'PayoutBatchList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PayoutBatchList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'batches';
    yield serializers.serialize(
      object.batches,
      specifiedType: const FullType(BuiltList, [FullType(PayoutBatch)]),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PayoutBatchList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PayoutBatchListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'batches':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PayoutBatch)]),
          ) as BuiltList<PayoutBatch>;
          result.batches.replace(valueDes);
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.total = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PayoutBatchList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PayoutBatchListBuilder();
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

