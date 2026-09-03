//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'payout_config.g.dart';

/// The single-row guard-payout settings (company debit accounts + ภ.ง.ด. terms).
///
/// Properties:
/// * [debitAccount] - Company account the transfers are debited from.
/// * [feeDebitAccount] - Account the transfer fees are debited from (defaults to the debit account).
/// * [whtFormTypeCode] - ภ.ง.ด. form code (53 = payments to a company).
/// * [whtPayTypeCode] 
/// * [whtIncomeTypeCode] - Assessable-income type (service fee).
/// * [whtIncomeDesc] 
/// * [whtRatePercent] - Withholding rate percent (exact decimal, string).
/// * [productCode] - SCB product (PromptPay credit).
/// * [updatedAt] - null until first saved.
@BuiltValue()
abstract class PayoutConfig implements Built<PayoutConfig, PayoutConfigBuilder> {
  /// Company account the transfers are debited from.
  @BuiltValueField(wireName: r'debit_account')
  String? get debitAccount;

  /// Account the transfer fees are debited from (defaults to the debit account).
  @BuiltValueField(wireName: r'fee_debit_account')
  String? get feeDebitAccount;

  /// ภ.ง.ด. form code (53 = payments to a company).
  @BuiltValueField(wireName: r'wht_form_type_code')
  String? get whtFormTypeCode;

  @BuiltValueField(wireName: r'wht_pay_type_code')
  String? get whtPayTypeCode;

  /// Assessable-income type (service fee).
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

