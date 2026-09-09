//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/preview_refund_recipient.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/excluded_customer.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refund_preview.g.dart';

/// RefundPreview
///
/// Properties:
/// * [recipients] 
/// * [excluded] 
/// * [recipientCount] 
/// * [totalAmount] - Σ transfers the file would debit (2dp string).
@BuiltValue()
abstract class RefundPreview implements Built<RefundPreview, RefundPreviewBuilder> {
  @BuiltValueField(wireName: r'recipients')
  BuiltList<PreviewRefundRecipient> get recipients;

  @BuiltValueField(wireName: r'excluded')
  BuiltList<ExcludedCustomer> get excluded;

  @BuiltValueField(wireName: r'recipient_count')
  int get recipientCount;

  /// Σ transfers the file would debit (2dp string).
  @BuiltValueField(wireName: r'total_amount')
  String get totalAmount;

  RefundPreview._();

  factory RefundPreview([void updates(RefundPreviewBuilder b)]) = _$RefundPreview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RefundPreviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RefundPreview> get serializer => _$RefundPreviewSerializer();
}

class _$RefundPreviewSerializer implements PrimitiveSerializer<RefundPreview> {
  @override
  final Iterable<Type> types = const [RefundPreview, _$RefundPreview];

  @override
  final String wireName = r'RefundPreview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RefundPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'recipients';
    yield serializers.serialize(
      object.recipients,
      specifiedType: const FullType(BuiltList, [FullType(PreviewRefundRecipient)]),
    );
    yield r'excluded';
    yield serializers.serialize(
      object.excluded,
      specifiedType: const FullType(BuiltList, [FullType(ExcludedCustomer)]),
    );
    yield r'recipient_count';
    yield serializers.serialize(
      object.recipientCount,
      specifiedType: const FullType(int),
    );
    yield r'total_amount';
    yield serializers.serialize(
      object.totalAmount,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RefundPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RefundPreviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'recipients':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PreviewRefundRecipient)]),
          ) as BuiltList<PreviewRefundRecipient>;
          result.recipients.replace(valueDes);
          break;
        case r'excluded':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ExcludedCustomer)]),
          ) as BuiltList<ExcludedCustomer>;
          result.excluded.replace(valueDes);
          break;
        case r'recipient_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.recipientCount = valueDes;
          break;
        case r'total_amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.totalAmount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RefundPreview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RefundPreviewBuilder();
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

