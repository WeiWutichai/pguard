//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/excluded_job.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/preview_cut_job.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'deduction_preview.g.dart';

/// The per-component totals of a sweep. VAT and the guard income still owed are reported ALONGSIDE and are explicitly NOT part of `total_amount` — the question this screen answers (\"what happens to the money in the receiving account?\") has three answers, and showing only one invites the other two to be swept by mistake later.  `total_amount` = `billed_cut_total − uncollected_total`, and both halves are shown: money the platform earned on a bill the customer never fully paid must be visible as such, not silently missing from the figure an admin reconciles the transfer against. 
///
/// Properties:
/// * [jobCount] 
/// * [totalAmount] - What the file transfers: `billed_cut_total − uncollected_total`.
/// * [commissionTotal] 
/// * [cancellationFeeTotal] 
/// * [tipTotal] 
/// * [unpaidGuardShareTotal] 
/// * [roundingAdjustmentTotal] - May be negative.
/// * [billedCutTotal] - Σ of the five components above — what the settled BILLS earned, before asking whether the customer transferred it.
/// * [uncollectedTotal] - BILLED AND NEVER COLLECTED — the reconcile's `Extra` arm wrote a settled bill above the pre-payment and captured nothing. DEDUCTED from `total_amount`, and given its own line so an admin can see that billed-but-unpaid money exists. Sweeping it would move baht that never arrived out of an account that also holds the Revenue Department's VAT and the guards' unpaid income. 
/// * [vatNotSwept] - Collected FOR the Revenue Department and remitted via ภ.พ.30 — shown so it is visible
/// * [guardIncomeNotSwept] - Still owed to guards out of these jobs; it leaves via the guard-payout file (stream ③)
/// * [excluded] - Capped at 500 rows; `excluded_count` is the true total.
/// * [excludedCount] 
/// * [jobs] - The per-job ledger, capped at 500 rows. The TOTALS above always cover every job in the window.
/// * [jobsTruncated] 
/// * [creditAccountMasked] - The destination masked to its last 4. `null` when no revenue account is configured — so the screen can say so instead of the export being where an admin finds out.
@BuiltValue()
abstract class DeductionPreview implements Built<DeductionPreview, DeductionPreviewBuilder> {
  @BuiltValueField(wireName: r'job_count')
  int get jobCount;

  /// What the file transfers: `billed_cut_total − uncollected_total`.
  @BuiltValueField(wireName: r'total_amount')
  String get totalAmount;

  @BuiltValueField(wireName: r'commission_total')
  String get commissionTotal;

  @BuiltValueField(wireName: r'cancellation_fee_total')
  String get cancellationFeeTotal;

  @BuiltValueField(wireName: r'tip_total')
  String get tipTotal;

  @BuiltValueField(wireName: r'unpaid_guard_share_total')
  String get unpaidGuardShareTotal;

  /// May be negative.
  @BuiltValueField(wireName: r'rounding_adjustment_total')
  String get roundingAdjustmentTotal;

  /// Σ of the five components above — what the settled BILLS earned, before asking whether the customer transferred it.
  @BuiltValueField(wireName: r'billed_cut_total')
  String get billedCutTotal;

  /// BILLED AND NEVER COLLECTED — the reconcile's `Extra` arm wrote a settled bill above the pre-payment and captured nothing. DEDUCTED from `total_amount`, and given its own line so an admin can see that billed-but-unpaid money exists. Sweeping it would move baht that never arrived out of an account that also holds the Revenue Department's VAT and the guards' unpaid income. 
  @BuiltValueField(wireName: r'uncollected_total')
  String get uncollectedTotal;

  /// Collected FOR the Revenue Department and remitted via ภ.พ.30 — shown so it is visible
  @BuiltValueField(wireName: r'vat_not_swept')
  String get vatNotSwept;

  /// Still owed to guards out of these jobs; it leaves via the guard-payout file (stream ③)
  @BuiltValueField(wireName: r'guard_income_not_swept')
  String get guardIncomeNotSwept;

  /// Capped at 500 rows; `excluded_count` is the true total.
  @BuiltValueField(wireName: r'excluded')
  BuiltList<ExcludedJob> get excluded;

  @BuiltValueField(wireName: r'excluded_count')
  int get excludedCount;

  /// The per-job ledger, capped at 500 rows. The TOTALS above always cover every job in the window.
  @BuiltValueField(wireName: r'jobs')
  BuiltList<PreviewCutJob> get jobs;

  @BuiltValueField(wireName: r'jobs_truncated')
  bool get jobsTruncated;

  /// The destination masked to its last 4. `null` when no revenue account is configured — so the screen can say so instead of the export being where an admin finds out.
  @BuiltValueField(wireName: r'credit_account_masked')
  String? get creditAccountMasked;

  DeductionPreview._();

  factory DeductionPreview([void updates(DeductionPreviewBuilder b)]) = _$DeductionPreview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeductionPreviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeductionPreview> get serializer => _$DeductionPreviewSerializer();
}

class _$DeductionPreviewSerializer implements PrimitiveSerializer<DeductionPreview> {
  @override
  final Iterable<Type> types = const [DeductionPreview, _$DeductionPreview];

  @override
  final String wireName = r'DeductionPreview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeductionPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'job_count';
    yield serializers.serialize(
      object.jobCount,
      specifiedType: const FullType(int),
    );
    yield r'total_amount';
    yield serializers.serialize(
      object.totalAmount,
      specifiedType: const FullType(String),
    );
    yield r'commission_total';
    yield serializers.serialize(
      object.commissionTotal,
      specifiedType: const FullType(String),
    );
    yield r'cancellation_fee_total';
    yield serializers.serialize(
      object.cancellationFeeTotal,
      specifiedType: const FullType(String),
    );
    yield r'tip_total';
    yield serializers.serialize(
      object.tipTotal,
      specifiedType: const FullType(String),
    );
    yield r'unpaid_guard_share_total';
    yield serializers.serialize(
      object.unpaidGuardShareTotal,
      specifiedType: const FullType(String),
    );
    yield r'rounding_adjustment_total';
    yield serializers.serialize(
      object.roundingAdjustmentTotal,
      specifiedType: const FullType(String),
    );
    yield r'billed_cut_total';
    yield serializers.serialize(
      object.billedCutTotal,
      specifiedType: const FullType(String),
    );
    yield r'uncollected_total';
    yield serializers.serialize(
      object.uncollectedTotal,
      specifiedType: const FullType(String),
    );
    yield r'vat_not_swept';
    yield serializers.serialize(
      object.vatNotSwept,
      specifiedType: const FullType(String),
    );
    yield r'guard_income_not_swept';
    yield serializers.serialize(
      object.guardIncomeNotSwept,
      specifiedType: const FullType(String),
    );
    yield r'excluded';
    yield serializers.serialize(
      object.excluded,
      specifiedType: const FullType(BuiltList, [FullType(ExcludedJob)]),
    );
    yield r'excluded_count';
    yield serializers.serialize(
      object.excludedCount,
      specifiedType: const FullType(int),
    );
    yield r'jobs';
    yield serializers.serialize(
      object.jobs,
      specifiedType: const FullType(BuiltList, [FullType(PreviewCutJob)]),
    );
    yield r'jobs_truncated';
    yield serializers.serialize(
      object.jobsTruncated,
      specifiedType: const FullType(bool),
    );
    if (object.creditAccountMasked != null) {
      yield r'credit_account_masked';
      yield serializers.serialize(
        object.creditAccountMasked,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DeductionPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeductionPreviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'job_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.jobCount = valueDes;
          break;
        case r'total_amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.totalAmount = valueDes;
          break;
        case r'commission_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.commissionTotal = valueDes;
          break;
        case r'cancellation_fee_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cancellationFeeTotal = valueDes;
          break;
        case r'tip_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.tipTotal = valueDes;
          break;
        case r'unpaid_guard_share_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.unpaidGuardShareTotal = valueDes;
          break;
        case r'rounding_adjustment_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.roundingAdjustmentTotal = valueDes;
          break;
        case r'billed_cut_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.billedCutTotal = valueDes;
          break;
        case r'uncollected_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.uncollectedTotal = valueDes;
          break;
        case r'vat_not_swept':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.vatNotSwept = valueDes;
          break;
        case r'guard_income_not_swept':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardIncomeNotSwept = valueDes;
          break;
        case r'excluded':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ExcludedJob)]),
          ) as BuiltList<ExcludedJob>;
          result.excluded.replace(valueDes);
          break;
        case r'excluded_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.excludedCount = valueDes;
          break;
        case r'jobs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PreviewCutJob)]),
          ) as BuiltList<PreviewCutJob>;
          result.jobs.replace(valueDes);
          break;
        case r'jobs_truncated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.jobsTruncated = valueDes;
          break;
        case r'credit_account_masked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.creditAccountMasked = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeductionPreview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeductionPreviewBuilder();
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

