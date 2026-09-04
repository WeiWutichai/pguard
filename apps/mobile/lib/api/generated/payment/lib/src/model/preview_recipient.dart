//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'preview_recipient.g.dart';

/// PreviewRecipient
///
/// Properties:
/// * [guardId] - Send this id back in `ExportPayoutRequest.guard_ids` to pay exactly this guard.
/// * [name] 
/// * [proxyMasked] - PromptPay proxy masked to its last 4 (PII).
/// * [jobCount] - Finished jobs this row's amounts cover (one TXNDET pays them all).
/// * [income] - Assessable income (2dp string).
/// * [wht] - Withholding tax (2dp string).
/// * [transfer] - Net PromptPay transfer = income − WHT (2dp string).
@BuiltValue()
abstract class PreviewRecipient implements Built<PreviewRecipient, PreviewRecipientBuilder> {
  /// Send this id back in `ExportPayoutRequest.guard_ids` to pay exactly this guard.
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  @BuiltValueField(wireName: r'name')
  String get name;

  /// PromptPay proxy masked to its last 4 (PII).
  @BuiltValueField(wireName: r'proxy_masked')
  String get proxyMasked;

  /// Finished jobs this row's amounts cover (one TXNDET pays them all).
  @BuiltValueField(wireName: r'job_count')
  int get jobCount;

  /// Assessable income (2dp string).
  @BuiltValueField(wireName: r'income')
  String get income;

  /// Withholding tax (2dp string).
  @BuiltValueField(wireName: r'wht')
  String get wht;

  /// Net PromptPay transfer = income − WHT (2dp string).
  @BuiltValueField(wireName: r'transfer')
  String get transfer;

  PreviewRecipient._();

  factory PreviewRecipient([void updates(PreviewRecipientBuilder b)]) = _$PreviewRecipient;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PreviewRecipientBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PreviewRecipient> get serializer => _$PreviewRecipientSerializer();
}

class _$PreviewRecipientSerializer implements PrimitiveSerializer<PreviewRecipient> {
  @override
  final Iterable<Type> types = const [PreviewRecipient, _$PreviewRecipient];

  @override
  final String wireName = r'PreviewRecipient';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PreviewRecipient object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
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
    yield r'job_count';
    yield serializers.serialize(
      object.jobCount,
      specifiedType: const FullType(int),
    );
    yield r'income';
    yield serializers.serialize(
      object.income,
      specifiedType: const FullType(String),
    );
    yield r'wht';
    yield serializers.serialize(
      object.wht,
      specifiedType: const FullType(String),
    );
    yield r'transfer';
    yield serializers.serialize(
      object.transfer,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PreviewRecipient object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PreviewRecipientBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
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
        case r'job_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.jobCount = valueDes;
          break;
        case r'income':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.income = valueDes;
          break;
        case r'wht':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.wht = valueDes;
          break;
        case r'transfer':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.transfer = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PreviewRecipient deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PreviewRecipientBuilder();
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

