//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'payout_config.g.dart';

/// The single-row guard-payout settings (company debit accounts + ภ.ง.ด. terms).
///
/// Properties:
/// * [debitAccount] - Company account the transfers are debited from.
/// * [feeDebitAccount] - Account the transfer fees are debited from (defaults to the debit account).
/// * [revenueAccount] - The company SCB account the PLATFORM-CUT sweep (stream ②, product `OAT`) is CREDITED to. `null` until an admin sets it; `POST /admin/deductions/export` refuses to run without it. Validated as a real SCB account (10 digits passing the §14 check digit) at save time AND again at export — an `OAT` line may credit no other bank, and a check-digit typo is BATCH-fatal: SCB rejects the file after the jobs in it were marked swept. 
/// * [whtFormTypeCode] - ภ.ง.ด. form code. SCB accepts exactly seven values — `01`, `03`, `04`, `11`, `12`, `13`, `53` (`Master_data!TBWHTType`) — and they are NOT sequential, so treat them as a lookup, never a range. `04` = ภ.ง.ด.3 (payments to an individual), `53` = ภ.ง.ด.53 (payments to a juristic person). A guard paid on a 13-digit national-id PromptPay proxy is an individual. 
/// * [whtPayTypeCode] - `Master_data!TBWHTPayType`: `1` ผู้จ่ายออกครั้งเดียว, `2` ออกให้ตลอดไป, `3` หักภาษี ณ ที่จ่าย, `4` อื่นๆ. `4` is a real SCB code but NOT supported here — it requires a free-text remark on the certificate that pguard does not model, so saving it is a 400. 
/// * [whtIncomeTypeCode] - Assessable-income type (`Master_data!TBIncomeType`). Fifteen codes, and they are NOT integers: `1`, `2`, `3`, `4a`, `4b1.1`…`4b1.4`, `4b2.1`…`4b2.5`, `5`, `6`. Security service fee is `5`. 
/// * [whtIncomeDesc] 
/// * [whtRatePercent] - Withholding rate percent (exact decimal, string).
/// * [productCode] - SCB product (PromptPay credit).
/// * [feeChargeCode] - Who bears the transfer fee (`Master_data!TBFeeOther`) — it rides EVERY credit line (`TXNDET` field 8) and the bank requires it. `OUR` = the company pays the fee, which is the payout default because it is the only value that leaves the guard receiving exactly the amount our ledger records; `BEN` deducts the fee from the guard's credit, so our books and the bank's would disagree about the same transfer. 
/// * [smsNotify] - Whether SCB should SMS the guard about the transfer (`TXNDET` fields 9/10). OFF by default: the bank bills per message and the number is the guard's login phone. It does NOT affect how the money is addressed — the same phone is still the PromptPay `MOB` proxy for a guard with no tax id. 
/// * [maxTransferPerTxn] - Per-transaction transfer cap in THB (exact decimal, string; null = uncapped). A guard whose TOTAL transfer exceeds it is EXCLUDED from the batch with a reason rather than written as a line SCB would reject. Default `2000000` — the SMART/ORFT/PromptPay limit for a `NAT`/`MOB` proxy (the ฿10,000 figure applies only to a 15-digit E-Wallet proxy). 
/// * [updatedAt] - null until first saved.
@BuiltValue()
abstract class PayoutConfig implements Built<PayoutConfig, PayoutConfigBuilder> {
  /// Company account the transfers are debited from.
  @BuiltValueField(wireName: r'debit_account')
  String? get debitAccount;

  /// Account the transfer fees are debited from (defaults to the debit account).
  @BuiltValueField(wireName: r'fee_debit_account')
  String? get feeDebitAccount;

  /// The company SCB account the PLATFORM-CUT sweep (stream ②, product `OAT`) is CREDITED to. `null` until an admin sets it; `POST /admin/deductions/export` refuses to run without it. Validated as a real SCB account (10 digits passing the §14 check digit) at save time AND again at export — an `OAT` line may credit no other bank, and a check-digit typo is BATCH-fatal: SCB rejects the file after the jobs in it were marked swept. 
  @BuiltValueField(wireName: r'revenue_account')
  String? get revenueAccount;

  /// ภ.ง.ด. form code. SCB accepts exactly seven values — `01`, `03`, `04`, `11`, `12`, `13`, `53` (`Master_data!TBWHTType`) — and they are NOT sequential, so treat them as a lookup, never a range. `04` = ภ.ง.ด.3 (payments to an individual), `53` = ภ.ง.ด.53 (payments to a juristic person). A guard paid on a 13-digit national-id PromptPay proxy is an individual. 
  @BuiltValueField(wireName: r'wht_form_type_code')
  String? get whtFormTypeCode;

  /// `Master_data!TBWHTPayType`: `1` ผู้จ่ายออกครั้งเดียว, `2` ออกให้ตลอดไป, `3` หักภาษี ณ ที่จ่าย, `4` อื่นๆ. `4` is a real SCB code but NOT supported here — it requires a free-text remark on the certificate that pguard does not model, so saving it is a 400. 
  @BuiltValueField(wireName: r'wht_pay_type_code')
  String? get whtPayTypeCode;

  /// Assessable-income type (`Master_data!TBIncomeType`). Fifteen codes, and they are NOT integers: `1`, `2`, `3`, `4a`, `4b1.1`…`4b1.4`, `4b2.1`…`4b2.5`, `5`, `6`. Security service fee is `5`. 
  @BuiltValueField(wireName: r'wht_income_type_code')
  String? get whtIncomeTypeCode;

  @BuiltValueField(wireName: r'wht_income_desc')
  String? get whtIncomeDesc;

  /// Withholding rate percent (exact decimal, string).
  @BuiltValueField(wireName: r'wht_rate_percent')
  String? get whtRatePercent;

  /// SCB product (PromptPay credit).
  @BuiltValueField(wireName: r'product_code')
  String? get productCode;

  /// Who bears the transfer fee (`Master_data!TBFeeOther`) — it rides EVERY credit line (`TXNDET` field 8) and the bank requires it. `OUR` = the company pays the fee, which is the payout default because it is the only value that leaves the guard receiving exactly the amount our ledger records; `BEN` deducts the fee from the guard's credit, so our books and the bank's would disagree about the same transfer. 
  @BuiltValueField(wireName: r'fee_charge_code')
  PayoutConfigFeeChargeCodeEnum? get feeChargeCode;
  // enum feeChargeCodeEnum {  OUR,  BEN,  };

  /// Whether SCB should SMS the guard about the transfer (`TXNDET` fields 9/10). OFF by default: the bank bills per message and the number is the guard's login phone. It does NOT affect how the money is addressed — the same phone is still the PromptPay `MOB` proxy for a guard with no tax id. 
  @BuiltValueField(wireName: r'sms_notify')
  bool? get smsNotify;

  /// Per-transaction transfer cap in THB (exact decimal, string; null = uncapped). A guard whose TOTAL transfer exceeds it is EXCLUDED from the batch with a reason rather than written as a line SCB would reject. Default `2000000` — the SMART/ORFT/PromptPay limit for a `NAT`/`MOB` proxy (the ฿10,000 figure applies only to a 15-digit E-Wallet proxy). 
  @BuiltValueField(wireName: r'max_transfer_per_txn')
  String? get maxTransferPerTxn;

  /// null until first saved.
  @BuiltValueField(wireName: r'updated_at')
  DateTime? get updatedAt;

  PayoutConfig._();

  factory PayoutConfig([void updates(PayoutConfigBuilder b)]) = _$PayoutConfig;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PayoutConfigBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PayoutConfig> get serializer => _$PayoutConfigSerializer();
}

class _$PayoutConfigSerializer implements PrimitiveSerializer<PayoutConfig> {
  @override
  final Iterable<Type> types = const [PayoutConfig, _$PayoutConfig];

  @override
  final String wireName = r'PayoutConfig';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PayoutConfig object, {
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
    if (object.whtRatePercent != null) {
      yield r'wht_rate_percent';
      yield serializers.serialize(
        object.whtRatePercent,
        specifiedType: const FullType(String),
      );
    }
    if (object.productCode != null) {
      yield r'product_code';
      yield serializers.serialize(
        object.productCode,
        specifiedType: const FullType(String),
      );
    }
    if (object.feeChargeCode != null) {
      yield r'fee_charge_code';
      yield serializers.serialize(
        object.feeChargeCode,
        specifiedType: const FullType(PayoutConfigFeeChargeCodeEnum),
      );
    }
    if (object.smsNotify != null) {
      yield r'sms_notify';
      yield serializers.serialize(
        object.smsNotify,
        specifiedType: const FullType(bool),
      );
    }
    if (object.maxTransferPerTxn != null) {
      yield r'max_transfer_per_txn';
      yield serializers.serialize(
        object.maxTransferPerTxn,
        specifiedType: const FullType(String),
      );
    }
    if (object.updatedAt != null) {
      yield r'updated_at';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PayoutConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PayoutConfigBuilder result,
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
        case r'wht_rate_percent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.whtRatePercent = valueDes;
          break;
        case r'product_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.productCode = valueDes;
          break;
        case r'fee_charge_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PayoutConfigFeeChargeCodeEnum),
          ) as PayoutConfigFeeChargeCodeEnum;
          result.feeChargeCode = valueDes;
          break;
        case r'sms_notify':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.smsNotify = valueDes;
          break;
        case r'max_transfer_per_txn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.maxTransferPerTxn = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PayoutConfig deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PayoutConfigBuilder();
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

class PayoutConfigFeeChargeCodeEnum extends EnumClass {

  /// Who bears the transfer fee (`Master_data!TBFeeOther`) — it rides EVERY credit line (`TXNDET` field 8) and the bank requires it. `OUR` = the company pays the fee, which is the payout default because it is the only value that leaves the guard receiving exactly the amount our ledger records; `BEN` deducts the fee from the guard's credit, so our books and the bank's would disagree about the same transfer. 
  @BuiltValueEnumConst(wireName: r'OUR')
  static const PayoutConfigFeeChargeCodeEnum OUR = _$payoutConfigFeeChargeCodeEnum_OUR;
  /// Who bears the transfer fee (`Master_data!TBFeeOther`) — it rides EVERY credit line (`TXNDET` field 8) and the bank requires it. `OUR` = the company pays the fee, which is the payout default because it is the only value that leaves the guard receiving exactly the amount our ledger records; `BEN` deducts the fee from the guard's credit, so our books and the bank's would disagree about the same transfer. 
  @BuiltValueEnumConst(wireName: r'BEN')
  static const PayoutConfigFeeChargeCodeEnum BEN = _$payoutConfigFeeChargeCodeEnum_BEN;

  static Serializer<PayoutConfigFeeChargeCodeEnum> get serializer => _$payoutConfigFeeChargeCodeEnumSerializer;

  const PayoutConfigFeeChargeCodeEnum._(String name): super(name);

  static BuiltSet<PayoutConfigFeeChargeCodeEnum> get values => _$payoutConfigFeeChargeCodeEnumValues;
  static PayoutConfigFeeChargeCodeEnum valueOf(String name) => _$payoutConfigFeeChargeCodeEnumValueOf(name);
}

