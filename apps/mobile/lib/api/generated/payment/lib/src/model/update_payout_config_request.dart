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
/// * [whtFormTypeCode] 
/// * [whtPayTypeCode] 
/// * [whtIncomeTypeCode] 
/// * [whtIncomeDesc] 
/// * [whtRatePercent] - 0–100 (exact decimal, string).
@BuiltValue()
abstract class UpdatePayoutConfigRequest implements Built<UpdatePayoutConfigRequest, UpdatePayoutConfigRequestBuilder> {
  @BuiltValueField(wireName: r'debit_account')
  String? get debitAccount;

  @BuiltValueField(wireName: r'fee_debit_account')
  String? get feeDebitAccount;

  @BuiltValueField(wireName: r'wht_form_type_code')
  String? get whtFormTypeCode;

  @BuiltValueField(wireName: r'wht_pay_type_code')
  String? get whtPayTypeCode;

  @BuiltValueField(wireName: r'wht_income_type_code')
  String? get whtIncomeTypeCode;

  @BuiltValueField(wireName: r'wht_income_desc')
  String? get whtIncomeDesc;

  /// 0–100 (exact decimal, string).
  @BuiltValueField(wireName: r'wht_rate_percent')
  String? get whtRatePercent;

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

