//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'preview_cut_job.g.dart';

/// One job's cut, every component itemised so an accountant can see WHY it contributes what it does.
///
/// Properties:
/// * [paymentId] 
/// * [bookingId] 
/// * [settledOn] - The Bangkok day the job was settled — the basis the window filters on.
/// * [commission] - Deducted from the guard's pay (exact decimal, string).
/// * [cancellationFee] - The VAT-EXCLUSIVE part of a retained cancellation fee.
/// * [tip] - In the cut only because of a KNOWN, DEFERRED bug: the customer is billed a gratuity the guard never receives.
/// * [unpaidGuardShare] - In the cut only because of a KNOWN, DEFERRED bug: a booking billed for N guards pays exactly one.
/// * [roundingAdjustment] - Satang of drift between prorating on the unrounded worked-hours ratio and paying on actual_hours rounded to 2 dp. May be NEGATIVE — the platform really can be marginally out of pocket on one job.
/// * [uncollected] - BILLED AND NEVER COLLECTED, and SUBTRACTED from `amount`. The completion reconcile's `Extra` arm records a settled bill above what the customer pre-paid and captures nothing, so this much of the cut is not in the bank. The guard's income and the VAT are owed in full whatever the customer transferred, so the whole shortfall falls on the platform's share rather than being pro-rated across the components. 
/// * [amount] - The job's total cut = the five components LESS `uncollected`. May be NEGATIVE, in which case the job nets DOWN against the rest of the sweep.
@BuiltValue()
abstract class PreviewCutJob implements Built<PreviewCutJob, PreviewCutJobBuilder> {
  @BuiltValueField(wireName: r'payment_id')
  String get paymentId;

  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  /// The Bangkok day the job was settled — the basis the window filters on.
  @BuiltValueField(wireName: r'settled_on')
  Date get settledOn;

  /// Deducted from the guard's pay (exact decimal, string).
  @BuiltValueField(wireName: r'commission')
  String get commission;

  /// The VAT-EXCLUSIVE part of a retained cancellation fee.
  @BuiltValueField(wireName: r'cancellation_fee')
  String get cancellationFee;

  /// In the cut only because of a KNOWN, DEFERRED bug: the customer is billed a gratuity the guard never receives.
  @BuiltValueField(wireName: r'tip')
  String get tip;

  /// In the cut only because of a KNOWN, DEFERRED bug: a booking billed for N guards pays exactly one.
  @BuiltValueField(wireName: r'unpaid_guard_share')
  String get unpaidGuardShare;

  /// Satang of drift between prorating on the unrounded worked-hours ratio and paying on actual_hours rounded to 2 dp. May be NEGATIVE — the platform really can be marginally out of pocket on one job.
  @BuiltValueField(wireName: r'rounding_adjustment')
  String get roundingAdjustment;

  /// BILLED AND NEVER COLLECTED, and SUBTRACTED from `amount`. The completion reconcile's `Extra` arm records a settled bill above what the customer pre-paid and captures nothing, so this much of the cut is not in the bank. The guard's income and the VAT are owed in full whatever the customer transferred, so the whole shortfall falls on the platform's share rather than being pro-rated across the components. 
  @BuiltValueField(wireName: r'uncollected')
  String get uncollected;

  /// The job's total cut = the five components LESS `uncollected`. May be NEGATIVE, in which case the job nets DOWN against the rest of the sweep.
  @BuiltValueField(wireName: r'amount')
  String get amount;

  PreviewCutJob._();

  factory PreviewCutJob([void updates(PreviewCutJobBuilder b)]) = _$PreviewCutJob;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PreviewCutJobBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PreviewCutJob> get serializer => _$PreviewCutJobSerializer();
}

class _$PreviewCutJobSerializer implements PrimitiveSerializer<PreviewCutJob> {
  @override
  final Iterable<Type> types = const [PreviewCutJob, _$PreviewCutJob];

  @override
  final String wireName = r'PreviewCutJob';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PreviewCutJob object, {
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
    yield r'settled_on';
    yield serializers.serialize(
      object.settledOn,
      specifiedType: const FullType(Date),
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
  }

  @override
  Object serialize(
    Serializers serializers,
    PreviewCutJob object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PreviewCutJobBuilder result,
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
        case r'settled_on':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.settledOn = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PreviewCutJob deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PreviewCutJobBuilder();
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

