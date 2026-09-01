//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/excluded_guard.dart';
import 'package:pguard_payment_api/src/model/preview_recipient.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'payout_preview.g.dart';

/// PayoutPreview
///
/// Properties:
/// * [recipients] 
/// * [excluded] 
/// * [recipientCount] 
/// * [totalTransfer] - Σ net transfers (2dp string).
/// * [totalWht] - Σ withholding (2dp string).
@BuiltValue()
abstract class PayoutPreview implements Built<PayoutPreview, PayoutPreviewBuilder> {
  @BuiltValueField(wireName: r'recipients')
  BuiltList<PreviewRecipient> get recipients;

  @BuiltValueField(wireName: r'excluded')
  BuiltList<ExcludedGuard> get excluded;

  @BuiltValueField(wireName: r'recipient_count')
  int get recipientCount;

  /// Σ net transfers (2dp string).
  @BuiltValueField(wireName: r'total_transfer')
  String get totalTransfer;

  /// Σ withholding (2dp string).
  @BuiltValueField(wireName: r'total_wht')
  String get totalWht;

  PayoutPreview._();

  factory PayoutPreview([void updates(PayoutPreviewBuilder b)]) = _$PayoutPreview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PayoutPreviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PayoutPreview> get serializer => _$PayoutPreviewSerializer();
}

class _$PayoutPreviewSerializer implements PrimitiveSerializer<PayoutPreview> {
  @override
  final Iterable<Type> types = const [PayoutPreview, _$PayoutPreview];

  @override
  final String wireName = r'PayoutPreview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PayoutPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'recipients';
    yield serializers.serialize(
      object.recipients,
      specifiedType: const FullType(BuiltList, [FullType(PreviewRecipient)]),
    );
    yield r'excluded';
    yield serializers.serialize(
      object.excluded,
      specifiedType: const FullType(BuiltList, [FullType(ExcludedGuard)]),
    );
    yield r'recipient_count';
    yield serializers.serialize(
      object.recipientCount,
      specifiedType: const FullType(int),
    );
    yield r'total_transfer';
    yield serializers.serialize(
      object.totalTransfer,
      specifiedType: const FullType(String),
    );
    yield r'total_wht';
    yield serializers.serialize(
      object.totalWht,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PayoutPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PayoutPreviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'recipients':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PreviewRecipient)]),
          ) as BuiltList<PreviewRecipient>;
          result.recipients.replace(valueDes);
          break;
        case r'excluded':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ExcludedGuard)]),
          ) as BuiltList<ExcludedGuard>;
          result.excluded.replace(valueDes);
          break;
        case r'recipient_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.recipientCount = valueDes;
          break;
        case r'total_transfer':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.totalTransfer = valueDes;
          break;
        case r'total_wht':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.totalWht = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PayoutPreview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PayoutPreviewBuilder();
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

