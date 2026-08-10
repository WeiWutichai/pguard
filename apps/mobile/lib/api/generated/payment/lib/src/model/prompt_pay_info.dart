//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'prompt_pay_info.g.dart';

/// PromptPay transfer instructions for a booking. `qr_payload` is the authoritative EMVCo PromptPay QR string, generated server-side from `RECEIVING_ACCOUNT` + the estimate — the client renders it as a QR and never rebuilds it. 
///
/// Properties:
/// * [amount] - The server-side estimate to transfer (exact decimal as a string; money rule) — VAT-INCLUSIVE (`grand_total`), because that is the sum the customer actually sends.
/// * [amountSatang] - The same VAT-inclusive estimate in satang (the smallest THB unit, ×100) — a convenience field.
/// * [receivingAccount] - OUR receiving PromptPay account, formatted for human display.
/// * [qrPayload] - The authoritative EMVCo PromptPay QR payload (render as a QR; do NOT rebuild). Encodes the PromptPay AID + our proxy + the amount + currency THB + country TH + CRC. 
@BuiltValue()
abstract class PromptPayInfo implements Built<PromptPayInfo, PromptPayInfoBuilder> {
  /// The server-side estimate to transfer (exact decimal as a string; money rule) — VAT-INCLUSIVE (`grand_total`), because that is the sum the customer actually sends.
  @BuiltValueField(wireName: r'amount')
  String get amount;

  /// The same VAT-inclusive estimate in satang (the smallest THB unit, ×100) — a convenience field.
  @BuiltValueField(wireName: r'amount_satang')
  int get amountSatang;

  /// OUR receiving PromptPay account, formatted for human display.
  @BuiltValueField(wireName: r'receiving_account')
  String get receivingAccount;

  /// The authoritative EMVCo PromptPay QR payload (render as a QR; do NOT rebuild). Encodes the PromptPay AID + our proxy + the amount + currency THB + country TH + CRC. 
  @BuiltValueField(wireName: r'qr_payload')
  String get qrPayload;

  PromptPayInfo._();

  factory PromptPayInfo([void updates(PromptPayInfoBuilder b)]) = _$PromptPayInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PromptPayInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PromptPayInfo> get serializer => _$PromptPayInfoSerializer();
}

class _$PromptPayInfoSerializer implements PrimitiveSerializer<PromptPayInfo> {
  @override
  final Iterable<Type> types = const [PromptPayInfo, _$PromptPayInfo];

  @override
  final String wireName = r'PromptPayInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PromptPayInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'amount';
    yield serializers.serialize(
      object.amount,
      specifiedType: const FullType(String),
    );
    yield r'amount_satang';
    yield serializers.serialize(
      object.amountSatang,
      specifiedType: const FullType(int),
    );
    yield r'receiving_account';
    yield serializers.serialize(
      object.receivingAccount,
      specifiedType: const FullType(String),
    );
    yield r'qr_payload';
    yield serializers.serialize(
      object.qrPayload,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PromptPayInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PromptPayInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.amount = valueDes;
          break;
        case r'amount_satang':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.amountSatang = valueDes;
          break;
        case r'receiving_account':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.receivingAccount = valueDes;
          break;
        case r'qr_payload':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.qrPayload = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PromptPayInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PromptPayInfoBuilder();
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

