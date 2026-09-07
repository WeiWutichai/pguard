//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_payout_config_request.g.dart';

/// Every field optional — a null field keeps the stored value (or the default on first write).
///
/// Properties:
/// * [debitAccount] 
/// * [feeDebitAccount] 
/// * [revenueAccount] - The company account the platform-cut sweep credits. Must be a valid SCB account (10 digits + check digit) or it is a 400 on the settings screen rather than a bounced money file. Null keeps the stored value. 
/// * [whtFormTypeCode] - One of the seven ภ.ง.ด. codes (`01`, `03`, `04`, `11`, `12`, `13`, `53`); anything else is a 400. They are not a range — validate by lookup. 
/// * [whtPayTypeCode] - `1`, `2` or `3`. `4` (อื่นๆ) is refused with its own message: SCB requires a free-text pay-type remark alongside it and there is no field for one yet. 
/// * [whtIncomeTypeCode] - One of the fifteen `TBIncomeType` codes (`1`…`6`, `4a`, `4b1.1`…`4b2.5`); anything else is a 400.
/// * [whtIncomeDesc] 
/// * [feeChargeCode] - `OUR` (company pays the transfer fee — recommended) or `BEN` (deducted from the guard); anything else is a 400. Null keeps the stored value, so this mandatory credit-line field can never be blanked through this API. 
/// * [smsNotify] - Opt in/out of the bank's SMS to the guard. Null keeps the stored value.
/// * [whtRatePercent] - 0–100 (exact decimal, string).
/// * [maxTransferPerTxn] - Per-transaction transfer cap in THB (exact decimal, string). Must not be negative (400). Null keeps the stored value — like every field here, the cap cannot be CLEARED through this API, only changed. 
@BuiltValue()
abstract class UpdatePayoutConfigRequest implements Built<UpdatePayoutConfigRequest, UpdatePayoutConfigRequestBuilder> {
  @BuiltValueField(wireName: r'debit_account')
  String? get debitAccount;

  @BuiltValueField(wireName: r'fee_debit_account')
  String? get feeDebitAccount;

  /// The company account the platform-cut sweep credits. Must be a valid SCB account (10 digits + check digit) or it is a 400 on the settings screen rather than a bounced money file. Null keeps the stored value. 
  @BuiltValueField(wireName: r'revenue_account')
  String? get revenueAccount;

  /// One of the seven ภ.ง.ด. codes (`01`, `03`, `04`, `11`, `12`, `13`, `53`); anything else is a 400. They are not a range — validate by lookup. 
  @BuiltValueField(wireName: r'wht_form_type_code')
  String? get whtFormTypeCode;

  /// `1`, `2` or `3`. `4` (อื่นๆ) is refused with its own message: SCB requires a free-text pay-type remark alongside it and there is no field for one yet. 
  @BuiltValueField(wireName: r'wht_pay_type_code')
  String? get whtPayTypeCode;

  /// One of the fifteen `TBIncomeType` codes (`1`…`6`, `4a`, `4b1.1`…`4b2.5`); anything else is a 400.
  @BuiltValueField(wireName: r'wht_income_type_code')
  String? get whtIncomeTypeCode;

  @BuiltValueField(wireName: r'wht_income_desc')
  String? get whtIncomeDesc;

  /// `OUR` (company pays the transfer fee — recommended) or `BEN` (deducted from the guard); anything else is a 400. Null keeps the stored value, so this mandatory credit-line field can never be blanked through this API. 
  @BuiltValueField(wireName: r'fee_charge_code')
  String? get feeChargeCode;

  /// Opt in/out of the bank's SMS to the guard. Null keeps the stored value.
  @BuiltValueField(wireName: r'sms_notify')
  bool? get smsNotify;

  /// 0–100 (exact decimal, string).
  @BuiltValueField(wireName: r'wht_rate_percent')
  String? get whtRatePercent;

  /// Per-transaction transfer cap in THB (exact decimal, string). Must not be negative (400). Null keeps the stored value — like every field here, the cap cannot be CLEARED through this API, only changed. 
  @BuiltValueField(wireName: r'max_transfer_per_txn')
  String? get maxTransferPerTxn;

  UpdatePayoutConfigRequest._();

  factory UpdatePayoutConfigRequest([void updates(UpdatePayoutConfigRequestBuilder b)]) = _$UpdatePayoutConfigRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdatePayoutConfigRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdatePayoutConfigRequest> get serializer => _$UpdatePayoutConfigRequestSerializer();
}

class _$UpdatePayoutConfigRequestSerializer implements PrimitiveSerializer<UpdatePayoutConfigRequest> {
  @override
  final Iterable<Type> types = const [UpdatePayoutConfigRequest, _$UpdatePayoutConfigRequest];

  @override
  final String wireName = r'UpdatePayoutConfigRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdatePayoutConfigRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.debitAccount != null) {
      yield r'debit_account';
      yield serializers.serialize(
        object.debitAccount,
        specifiedType: const FullType(String),
      );
    }
    if (object.feeDebitAccount != null) {
      yield r'fee_debit_account';
      yield serializers.serialize(
        object.feeDebitAccount,
        specifiedType: const FullType(String),
      );
    }
    if (object.revenueAccount != null) {
      yield r'revenue_account';
      yield serializers.serialize(
        object.revenueAccount,
        specifiedType: const FullType(String),
      );
    }
    if (object.whtFormTypeCode != null) {
      yield r'wht_form_type_code';
      yield serializers.serialize(
        object.whtFormTypeCode,
        specifiedType: const FullType(String),
      );
    }
    if (object.whtPayTypeCode != null) {
      yield r'wht_pay_type_code';
      yield serializers.serialize(
        object.whtPayTypeCode,
        specifiedType: const FullType(String),
      );
    }
    if (object.whtIncomeTypeCode != null) {
      yield r'wht_income_type_code';
      yield serializers.serialize(
        object.whtIncomeTypeCode,
        specifiedType: const FullType(String),
      );
    }
    if (object.whtIncomeDesc != null) {
      yield r'wht_income_desc';
      yield serializers.serialize(
        object.whtIncomeDesc,
        specifiedType: const FullType(String),
      );
    }
    if (object.feeChargeCode != null) {
      yield r'fee_charge_code';
      yield serializers.serialize(
        object.feeChargeCode,
        specifiedType: const FullType(String),
      );
    }
    if (object.smsNotify != null) {
      yield r'sms_notify';
      yield serializers.serialize(
        object.smsNotify,
        specifiedType: const FullType(bool),
      );
    }
    if (object.whtRatePercent != null) {
      yield r'wht_rate_percent';
      yield serializers.serialize(
        object.whtRatePercent,
        specifiedType: const FullType(String),
      );
    }
    if (object.maxTransferPerTxn != null) {
      yield r'max_transfer_per_txn';
      yield serializers.serialize(
        object.maxTransferPerTxn,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdatePayoutConfigRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpdatePayoutConfigRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'debit_account':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.debitAccount = valueDes;
          break;
        case r'fee_debit_account':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.feeDebitAccount = valueDes;
          break;
        case r'revenue_account':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.revenueAccount = valueDes;
          break;
        case r'wht_form_type_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.whtFormTypeCode = valueDes;
          break;
        case r'wht_pay_type_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.whtPayTypeCode = valueDes;
          break;
        case r'wht_income_type_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.whtIncomeTypeCode = valueDes;
          break;
        case r'wht_income_desc':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.whtIncomeDesc = valueDes;
          break;
        case r'fee_charge_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.feeChargeCode = valueDes;
          break;
        case r'sms_notify':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.smsNotify = valueDes;
          break;
        case r'wht_rate_percent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.whtRatePercent = valueDes;
          break;
        case r'max_transfer_per_txn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.maxTransferPerTxn = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdatePayoutConfigRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdatePayoutConfigRequestBuilder();
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

