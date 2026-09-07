//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'deduction_batch_item.g.dart';

/// One JOB whose cut a sweep collected — a LEDGER row behind the file's single credit line, not a recipient. The components are stored separately so a report can still say what the money WAS after the two deferred bugs (tip, guard_count) are fixed. 
///
/// Properties:
/// * [id] 
/// * [paymentId] - The swept-marker key.
/// * [bookingId] 
/// * [commission] 
/// * [cancellationFee] 
/// * [tip] 
/// * [unpaidGuardShare] 
/// * [roundingAdjustment] - May be negative.
/// * [uncollected] - Billed and never collected — SUBTRACTED from `amount`. 0 on every ordinary job.
/// * [amount] - commission + cancellation_fee + tip + unpaid_guard_share + rounding_adjustment − uncollected (a DB CHECK enforces it). May be negative.
/// * [voidedAt] - Set = this job is back in the sweepable backlog (the row is kept as history, not deleted).
/// * [createdAt] 
@BuiltValue()
abstract class DeductionBatchItem implements Built<DeductionBatchItem, DeductionBatchItemBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The swept-marker key.
  @BuiltValueField(wireName: r'payment_id')
  String get paymentId;

  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  @BuiltValueField(wireName: r'commission')
  String get commission;

  @BuiltValueField(wireName: r'cancellation_fee')
  String get cancellationFee;

  @BuiltValueField(wireName: r'tip')
  String get tip;

  @BuiltValueField(wireName: r'unpaid_guard_share')
  String get unpaidGuardShare;

  /// May be negative.
  @BuiltValueField(wireName: r'rounding_adjustment')
  String get roundingAdjustment;

  /// Billed and never collected — SUBTRACTED from `amount`. 0 on every ordinary job.
  @BuiltValueField(wireName: r'uncollected')
  String get uncollected;

  /// commission + cancellation_fee + tip + unpaid_guard_share + rounding_adjustment − uncollected (a DB CHECK enforces it). May be negative.
  @BuiltValueField(wireName: r'amount')
  String get amount;

  /// Set = this job is back in the sweepable backlog (the row is kept as history, not deleted).
  @BuiltValueField(wireName: r'voided_at')
  DateTime? get voidedAt;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  DeductionBatchItem._();

  factory DeductionBatchItem([void updates(DeductionBatchItemBuilder b)]) = _$DeductionBatchItem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeductionBatchItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeductionBatchItem> get serializer => _$DeductionBatchItemSerializer();
}

class _$DeductionBatchItemSerializer implements PrimitiveSerializer<DeductionBatchItem> {
  @override
  final Iterable<Type> types = const [DeductionBatchItem, _$DeductionBatchItem];

  @override
  final String wireName = r'DeductionBatchItem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeductionBatchItem object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'payment_id';
    yield serializers.serialize(
      object.paymentId,
      specifiedType: const FullType(String),
    );
    yield r'booking_id';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
    yield r'commission';
    yield serializers.serialize(
      object.commission,
      specifiedType: const FullType(String),
    );
    yield r'cancellation_fee';
    yield serializers.serialize(
      object.cancellationFee,
      specifiedType: const FullType(String),
    );
    yield r'tip';
    yield serializers.serialize(
      object.tip,
      specifiedType: const FullType(String),
    );
    yield r'unpaid_guard_share';
    yield serializers.serialize(
      object.unpaidGuardShare,
      specifiedType: const FullType(String),
    );
    yield r'rounding_adjustment';
    yield serializers.serialize(
      object.roundingAdjustment,
      specifiedType: const FullType(String),
    );
    yield r'uncollected';
    yield serializers.serialize(
      object.uncollected,
      specifiedType: const FullType(String),
    );
    yield r'amount';
    yield serializers.serialize(
      object.amount,
      specifiedType: const FullType(String),
    );
    if (object.voidedAt != null) {
      yield r'voided_at';
      yield serializers.serialize(
        object.voidedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DeductionBatchItem object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeductionBatchItemBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'payment_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.paymentId = valueDes;
          break;
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'commission':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.commission = valueDes;
          break;
        case r'cancellation_fee':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cancellationFee = valueDes;
          break;
        case r'tip':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.tip = valueDes;
          break;
        case r'unpaid_guard_share':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.unpaidGuardShare = valueDes;
          break;
        case r'rounding_adjustment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.roundingAdjustment = valueDes;
          break;
        case r'uncollected':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.uncollected = valueDes;
          break;
        case r'amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.amount = valueDes;
          break;
        case r'voided_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.voidedAt = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeductionBatchItem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeductionBatchItemBuilder();
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

