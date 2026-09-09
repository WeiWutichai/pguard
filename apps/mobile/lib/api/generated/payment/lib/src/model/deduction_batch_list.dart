//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/deduction_batch.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'deduction_batch_list.g.dart';

/// DeductionBatchList
///
/// Properties:
/// * [batches] 
/// * [total] - Total matching batches
@BuiltValue()
abstract class DeductionBatchList implements Built<DeductionBatchList, DeductionBatchListBuilder> {
  @BuiltValueField(wireName: r'batches')
  BuiltList<DeductionBatch> get batches;

  /// Total matching batches
  @BuiltValueField(wireName: r'total')
  int get total;

  DeductionBatchList._();

  factory DeductionBatchList([void updates(DeductionBatchListBuilder b)]) = _$DeductionBatchList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeductionBatchListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeductionBatchList> get serializer => _$DeductionBatchListSerializer();
}

class _$DeductionBatchListSerializer implements PrimitiveSerializer<DeductionBatchList> {
  @override
  final Iterable<Type> types = const [DeductionBatchList, _$DeductionBatchList];

  @override
  final String wireName = r'DeductionBatchList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeductionBatchList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'batches';
    yield serializers.serialize(
      object.batches,
      specifiedType: const FullType(BuiltList, [FullType(DeductionBatch)]),
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
    DeductionBatchList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeductionBatchListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'batches':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DeductionBatch)]),
          ) as BuiltList<DeductionBatch>;
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
  DeductionBatchList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeductionBatchListBuilder();
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

