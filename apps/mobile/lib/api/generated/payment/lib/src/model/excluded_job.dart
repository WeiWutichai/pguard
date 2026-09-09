//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'excluded_job.g.dart';

/// A job whose cut could NOT be computed. Its cut is counted nowhere and it is NOT marked swept, so it reappears in the next preview instead of silently contributing zero — a report that under-states the platform's cut is worse than one that says \"N jobs unknown\". 
///
/// Properties:
/// * [paymentId] 
/// * [bookingId] 
/// * [code] - `NOT_SETTLED` — the reconcile has not run, so the cut is not final yet (it will be next run). `NO_VAT_SPLIT` — the charge predates the VAT split, so our money cannot be told from the Revenue Department's. `NO_PRICING_SNAPSHOT` — the charge predates the pricing snapshot; NOT recoverable, because `subtotal = base_fee × hours × guards + tip` is one equation in four unknowns and booking's current row is not what the job was billed on. `DOES_NOT_RECONCILE` — the stored money columns disagree with each other; a human question, never a number to sweep. 
/// * [reason] - The Thai sentence the admin reads.
@BuiltValue()
abstract class ExcludedJob implements Built<ExcludedJob, ExcludedJobBuilder> {
  @BuiltValueField(wireName: r'payment_id')
  String get paymentId;

  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  /// `NOT_SETTLED` — the reconcile has not run, so the cut is not final yet (it will be next run). `NO_VAT_SPLIT` — the charge predates the VAT split, so our money cannot be told from the Revenue Department's. `NO_PRICING_SNAPSHOT` — the charge predates the pricing snapshot; NOT recoverable, because `subtotal = base_fee × hours × guards + tip` is one equation in four unknowns and booking's current row is not what the job was billed on. `DOES_NOT_RECONCILE` — the stored money columns disagree with each other; a human question, never a number to sweep. 
  @BuiltValueField(wireName: r'code')
  ExcludedJobCodeEnum get code;
  // enum codeEnum {  NOT_SETTLED,  NO_VAT_SPLIT,  NO_PRICING_SNAPSHOT,  DOES_NOT_RECONCILE,  };

  /// The Thai sentence the admin reads.
  @BuiltValueField(wireName: r'reason')
  String get reason;

  ExcludedJob._();

  factory ExcludedJob([void updates(ExcludedJobBuilder b)]) = _$ExcludedJob;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ExcludedJobBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ExcludedJob> get serializer => _$ExcludedJobSerializer();
}

class _$ExcludedJobSerializer implements PrimitiveSerializer<ExcludedJob> {
  @override
  final Iterable<Type> types = const [ExcludedJob, _$ExcludedJob];

  @override
  final String wireName = r'ExcludedJob';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ExcludedJob object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(ExcludedJobCodeEnum),
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
    ExcludedJob object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ExcludedJobBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ExcludedJobCodeEnum),
          ) as ExcludedJobCodeEnum;
          result.code = valueDes;
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
  ExcludedJob deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ExcludedJobBuilder();
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

class ExcludedJobCodeEnum extends EnumClass {

  /// `NOT_SETTLED` — the reconcile has not run, so the cut is not final yet (it will be next run). `NO_VAT_SPLIT` — the charge predates the VAT split, so our money cannot be told from the Revenue Department's. `NO_PRICING_SNAPSHOT` — the charge predates the pricing snapshot; NOT recoverable, because `subtotal = base_fee × hours × guards + tip` is one equation in four unknowns and booking's current row is not what the job was billed on. `DOES_NOT_RECONCILE` — the stored money columns disagree with each other; a human question, never a number to sweep. 
  @BuiltValueEnumConst(wireName: r'NOT_SETTLED')
  static const ExcludedJobCodeEnum NOT_SETTLED = _$excludedJobCodeEnum_NOT_SETTLED;
  /// `NOT_SETTLED` — the reconcile has not run, so the cut is not final yet (it will be next run). `NO_VAT_SPLIT` — the charge predates the VAT split, so our money cannot be told from the Revenue Department's. `NO_PRICING_SNAPSHOT` — the charge predates the pricing snapshot; NOT recoverable, because `subtotal = base_fee × hours × guards + tip` is one equation in four unknowns and booking's current row is not what the job was billed on. `DOES_NOT_RECONCILE` — the stored money columns disagree with each other; a human question, never a number to sweep. 
  @BuiltValueEnumConst(wireName: r'NO_VAT_SPLIT')
  static const ExcludedJobCodeEnum NO_VAT_SPLIT = _$excludedJobCodeEnum_NO_VAT_SPLIT;
  /// `NOT_SETTLED` — the reconcile has not run, so the cut is not final yet (it will be next run). `NO_VAT_SPLIT` — the charge predates the VAT split, so our money cannot be told from the Revenue Department's. `NO_PRICING_SNAPSHOT` — the charge predates the pricing snapshot; NOT recoverable, because `subtotal = base_fee × hours × guards + tip` is one equation in four unknowns and booking's current row is not what the job was billed on. `DOES_NOT_RECONCILE` — the stored money columns disagree with each other; a human question, never a number to sweep. 
  @BuiltValueEnumConst(wireName: r'NO_PRICING_SNAPSHOT')
  static const ExcludedJobCodeEnum NO_PRICING_SNAPSHOT = _$excludedJobCodeEnum_NO_PRICING_SNAPSHOT;
  /// `NOT_SETTLED` — the reconcile has not run, so the cut is not final yet (it will be next run). `NO_VAT_SPLIT` — the charge predates the VAT split, so our money cannot be told from the Revenue Department's. `NO_PRICING_SNAPSHOT` — the charge predates the pricing snapshot; NOT recoverable, because `subtotal = base_fee × hours × guards + tip` is one equation in four unknowns and booking's current row is not what the job was billed on. `DOES_NOT_RECONCILE` — the stored money columns disagree with each other; a human question, never a number to sweep. 
  @BuiltValueEnumConst(wireName: r'DOES_NOT_RECONCILE')
  static const ExcludedJobCodeEnum DOES_NOT_RECONCILE = _$excludedJobCodeEnum_DOES_NOT_RECONCILE;

  static Serializer<ExcludedJobCodeEnum> get serializer => _$excludedJobCodeEnumSerializer;

  const ExcludedJobCodeEnum._(String name): super(name);

  static BuiltSet<ExcludedJobCodeEnum> get values => _$excludedJobCodeEnumValues;
  static ExcludedJobCodeEnum valueOf(String name) => _$excludedJobCodeEnumValueOf(name);
}

