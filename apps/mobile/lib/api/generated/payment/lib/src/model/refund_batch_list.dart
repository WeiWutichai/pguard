//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/refund_batch.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refund_batch_list.g.dart';

/// RefundBatchList
///
/// Properties:
/// * [batches] 
/// * [total] - Total batches matching
@BuiltValue()
abstract class RefundBatchList implements Built<RefundBatchList, RefundBatchListBuilder> {
  @BuiltValueField(wireName: r'batches')
  BuiltList<RefundBatch> get batches;

  /// Total batches matching
  @BuiltValueField(wireName: r'total')
  int get total;

  RefundBatchList._();

  factory RefundBatchList([void updates(RefundBatchListBuilder b)]) = _$RefundBatchList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RefundBatchListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RefundBatchList> get serializer => _$RefundBatchListSerializer();
}

class _$RefundBatchListSerializer implements PrimitiveSerializer<RefundBatchList> {
  @override
  final Iterable<Type> types = const [RefundBatchList, _$RefundBatchList];

  @override
  final String wireName = r'RefundBatchList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RefundBatchList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'batches';
    yield serializers.serialize(
      object.batches,
      specifiedType: const FullType(BuiltList, [FullType(RefundBatch)]),
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
    RefundBatchList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RefundBatchListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'batches':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RefundBatch)]),
          ) as BuiltList<RefundBatch>;
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
  RefundBatchList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RefundBatchListBuilder();
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

