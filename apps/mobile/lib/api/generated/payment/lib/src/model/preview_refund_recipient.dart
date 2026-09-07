//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'preview_refund_recipient.g.dart';

/// PreviewRefundRecipient
///
/// Properties:
/// * [customerId] - Send this id back in `ExportRefundRequest.customer_ids` to refund exactly this customer.
/// * [name] 
/// * [proxyMasked] - PromptPay proxy (the registration phone) masked to its last 4 (PII).
/// * [obligationCount] - Pending obligations this row's amount covers, across both lanes (one TXNDET returns them all).
/// * [amount] - Total to transfer back (2dp string).
@BuiltValue()
abstract class PreviewRefundRecipient implements Built<PreviewRefundRecipient, PreviewRefundRecipientBuilder> {
  /// Send this id back in `ExportRefundRequest.customer_ids` to refund exactly this customer.
  @BuiltValueField(wireName: r'customer_id')
  String get customerId;

  @BuiltValueField(wireName: r'name')
  String get name;

  /// PromptPay proxy (the registration phone) masked to its last 4 (PII).
  @BuiltValueField(wireName: r'proxy_masked')
  String get proxyMasked;

  /// Pending obligations this row's amount covers, across both lanes (one TXNDET returns them all).
  @BuiltValueField(wireName: r'obligation_count')
  int get obligationCount;

  /// Total to transfer back (2dp string).
  @BuiltValueField(wireName: r'amount')
  String get amount;

  PreviewRefundRecipient._();

  factory PreviewRefundRecipient([void updates(PreviewRefundRecipientBuilder b)]) = _$PreviewRefundRecipient;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PreviewRefundRecipientBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PreviewRefundRecipient> get serializer => _$PreviewRefundRecipientSerializer();
}

class _$PreviewRefundRecipientSerializer implements PrimitiveSerializer<PreviewRefundRecipient> {
  @override
  final Iterable<Type> types = const [PreviewRefundRecipient, _$PreviewRefundRecipient];

  @override
  final String wireName = r'PreviewRefundRecipient';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PreviewRefundRecipient object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'customer_id';
    yield serializers.serialize(
      object.customerId,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'proxy_masked';
    yield serializers.serialize(
      object.proxyMasked,
      specifiedType: const FullType(String),
    );
    yield r'obligation_count';
    yield serializers.serialize(
      object.obligationCount,
      specifiedType: const FullType(int),
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
    PreviewRefundRecipient object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PreviewRefundRecipientBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'customer_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.customerId = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'proxy_masked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.proxyMasked = valueDes;
          break;
        case r'obligation_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.obligationCount = valueDes;
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
  PreviewRefundRecipient deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PreviewRefundRecipientBuilder();
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

