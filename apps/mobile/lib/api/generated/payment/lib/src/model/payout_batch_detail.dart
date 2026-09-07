//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:pguard_payment_api/src/model/payout_batch_item.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/payout_batch.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'payout_batch_detail.g.dart';

/// PayoutBatchDetail
///
/// Properties:
/// * [id] 
/// * [fileRef] - HEADER field 1 = batch_ref || product code (e.g. `050926120000PPY`). NOT the download filename.
/// * [systemRef] 
/// * [batchRef] - BCHDET field 1 — the bare 12-digit DDMMYYHHMMSS Bangkok stamp.
/// * [valueDate] 
/// * [totalAmount] - Σ net transfers the file debits (2dp string).
/// * [recipientCount] - How many GUARDS the file pays (= TXNDET lines) — NOT how many bookings; a guard with three finished jobs is one recipient.
/// * [status] 
/// * [statusNote] - Free text kept with the latest status change (typically the bank's own message).
/// * [voidReason] 
/// * [hasFile] - Whether the file text is stored and can be re-downloaded (false for batches generated before the text was kept).
/// * [createdBy] 
/// * [createdAt] 
/// * [uploadedAt] 
/// * [confirmedAt] 
/// * [rejectedAt] 
/// * [voidedAt] 
/// * [voidedBy] 
/// * [items] 
@BuiltValue()
abstract class PayoutBatchDetail implements PayoutBatch, Built<PayoutBatchDetail, PayoutBatchDetailBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<PayoutBatchItem> get items;

  PayoutBatchDetail._();

  factory PayoutBatchDetail([void updates(PayoutBatchDetailBuilder b)]) = _$PayoutBatchDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PayoutBatchDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PayoutBatchDetail> get serializer => _$PayoutBatchDetailSerializer();
}

class _$PayoutBatchDetailSerializer implements PrimitiveSerializer<PayoutBatchDetail> {
  @override
  final Iterable<Type> types = const [PayoutBatchDetail, _$PayoutBatchDetail];

  @override
  final String wireName = r'PayoutBatchDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PayoutBatchDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.statusNote != null) {
      yield r'status_note';
      yield serializers.serialize(
        object.statusNote,
        specifiedType: const FullType(String),
      );
    }
    if (object.voidReason != null) {
      yield r'void_reason';
      yield serializers.serialize(
        object.voidReason,
        specifiedType: const FullType(String),
      );
    }
    yield r'system_ref';
    yield serializers.serialize(
      object.systemRef,
      specifiedType: const FullType(String),
    );
    yield r'value_date';
    yield serializers.serialize(
      object.valueDate,
      specifiedType: const FullType(Date),
    );
    yield r'total_amount';
    yield serializers.serialize(
      object.totalAmount,
      specifiedType: const FullType(String),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.voidedBy != null) {
      yield r'voided_by';
      yield serializers.serialize(
        object.voidedBy,
        specifiedType: const FullType(String),
      );
    }
    yield r'has_file';
    yield serializers.serialize(
      object.hasFile,
      specifiedType: const FullType(bool),
    );
    yield r'recipient_count';
    yield serializers.serialize(
      object.recipientCount,
      specifiedType: const FullType(int),
    );
    if (object.createdBy != null) {
      yield r'created_by';
      yield serializers.serialize(
        object.createdBy,
        specifiedType: const FullType(String),
      );
    }
    if (object.rejectedAt != null) {
      yield r'rejected_at';
      yield serializers.serialize(
        object.rejectedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.uploadedAt != null) {
      yield r'uploaded_at';
      yield serializers.serialize(
        object.uploadedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'batch_ref';
    yield serializers.serialize(
      object.batchRef,
      specifiedType: const FullType(String),
    );
    if (object.confirmedAt != null) {
      yield r'confirmed_at';
      yield serializers.serialize(
        object.confirmedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(PayoutBatchItem)]),
    );
    if (object.voidedAt != null) {
      yield r'voided_at';
      yield serializers.serialize(
        object.voidedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'file_ref';
    yield serializers.serialize(
      object.fileRef,
      specifiedType: const FullType(String),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(PayoutBatchStatusEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PayoutBatchDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PayoutBatchDetailBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'status_note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.statusNote = valueDes;
          break;
        case r'void_reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.voidReason = valueDes;
          break;
        case r'system_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.systemRef = valueDes;
          break;
        case r'value_date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.valueDate = valueDes;
          break;
        case r'total_amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.totalAmount = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'voided_by':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.voidedBy = valueDes;
          break;
        case r'has_file':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasFile = valueDes;
          break;
        case r'recipient_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.recipientCount = valueDes;
          break;
        case r'created_by':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.createdBy = valueDes;
          break;
        case r'rejected_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.rejectedAt = valueDes;
          break;
        case r'uploaded_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.uploadedAt = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'batch_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.batchRef = valueDes;
          break;
        case r'confirmed_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.confirmedAt = valueDes;
          break;
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PayoutBatchItem)]),
          ) as BuiltList<PayoutBatchItem>;
          result.items.replace(valueDes);
          break;
        case r'voided_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.voidedAt = valueDes;
          break;
        case r'file_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fileRef = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PayoutBatchStatusEnum),
          ) as PayoutBatchStatusEnum;
          result.status = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PayoutBatchDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PayoutBatchDetailBuilder();
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

class PayoutBatchDetailStatusEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'generated')
  static const PayoutBatchDetailStatusEnum generated = _$payoutBatchDetailStatusEnum_generated;
  @BuiltValueEnumConst(wireName: r'uploaded')
  static const PayoutBatchDetailStatusEnum uploaded = _$payoutBatchDetailStatusEnum_uploaded;
  @BuiltValueEnumConst(wireName: r'confirmed')
  static const PayoutBatchDetailStatusEnum confirmed = _$payoutBatchDetailStatusEnum_confirmed;
  @BuiltValueEnumConst(wireName: r'rejected')
  static const PayoutBatchDetailStatusEnum rejected = _$payoutBatchDetailStatusEnum_rejected;
  @BuiltValueEnumConst(wireName: r'voided')
  static const PayoutBatchDetailStatusEnum voided = _$payoutBatchDetailStatusEnum_voided;

  static Serializer<PayoutBatchDetailStatusEnum> get serializer => _$payoutBatchDetailStatusEnumSerializer;

  const PayoutBatchDetailStatusEnum._(String name): super(name);

  static BuiltSet<PayoutBatchDetailStatusEnum> get values => _$payoutBatchDetailStatusEnumValues;
  static PayoutBatchDetailStatusEnum valueOf(String name) => _$payoutBatchDetailStatusEnumValueOf(name);
}

