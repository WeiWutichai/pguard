//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/refund_batch_item.dart';
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/refund_batch.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refund_batch_detail.g.dart';

/// RefundBatchDetail
///
/// Properties:
/// * [id] 
/// * [fileRef] - HEADER field 1 = batch_ref || product code (e.g. `070926120000PPY`). NOT the download filename.
/// * [systemRef] - HEADER field 2 — `PGUARD-REFUND` (the payout file carries `PGUARD-PAYOUT`).
/// * [batchRef] - BCHDET field 1 — the bare 12-digit DDMMYYHHMMSS Bangkok stamp.
/// * [valueDate] 
/// * [totalAmount] - Σ transfers the file debits (2dp string).
/// * [recipientCount] - How many CUSTOMERS the file refunds (= TXNDET lines) — NOT how many obligations; a customer owed three refunds is one recipient.
/// * [status] 
/// * [statusNote] - Free text kept with the latest status change (typically the bank's own message).
/// * [voidReason] 
/// * [hasFile] - Whether the file text is stored and can be re-downloaded.
/// * [createdBy] 
/// * [createdAt] 
/// * [uploadedAt] 
/// * [confirmedAt] 
/// * [rejectedAt] 
/// * [voidedAt] 
/// * [voidedBy] 
/// * [items] 
@BuiltValue()
abstract class RefundBatchDetail implements RefundBatch, Built<RefundBatchDetail, RefundBatchDetailBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<RefundBatchItem> get items;

  RefundBatchDetail._();

  factory RefundBatchDetail([void updates(RefundBatchDetailBuilder b)]) = _$RefundBatchDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RefundBatchDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RefundBatchDetail> get serializer => _$RefundBatchDetailSerializer();
}

class _$RefundBatchDetailSerializer implements PrimitiveSerializer<RefundBatchDetail> {
  @override
  final Iterable<Type> types = const [RefundBatchDetail, _$RefundBatchDetail];

  @override
  final String wireName = r'RefundBatchDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RefundBatchDetail object, {
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
      specifiedType: const FullType(BuiltList, [FullType(RefundBatchItem)]),
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
      specifiedType: const FullType(RefundBatchStatusEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RefundBatchDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RefundBatchDetailBuilder result,
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
            specifiedType: const FullType(BuiltList, [FullType(RefundBatchItem)]),
          ) as BuiltList<RefundBatchItem>;
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
            specifiedType: const FullType(RefundBatchStatusEnum),
          ) as RefundBatchStatusEnum;
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
  RefundBatchDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RefundBatchDetailBuilder();
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

class RefundBatchDetailStatusEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'generated')
  static const RefundBatchDetailStatusEnum generated = _$refundBatchDetailStatusEnum_generated;
  @BuiltValueEnumConst(wireName: r'uploaded')
  static const RefundBatchDetailStatusEnum uploaded = _$refundBatchDetailStatusEnum_uploaded;
  @BuiltValueEnumConst(wireName: r'confirmed')
  static const RefundBatchDetailStatusEnum confirmed = _$refundBatchDetailStatusEnum_confirmed;
  @BuiltValueEnumConst(wireName: r'rejected')
  static const RefundBatchDetailStatusEnum rejected = _$refundBatchDetailStatusEnum_rejected;
  @BuiltValueEnumConst(wireName: r'voided')
  static const RefundBatchDetailStatusEnum voided = _$refundBatchDetailStatusEnum_voided;

  static Serializer<RefundBatchDetailStatusEnum> get serializer => _$refundBatchDetailStatusEnumSerializer;

  const RefundBatchDetailStatusEnum._(String name): super(name);

  static BuiltSet<RefundBatchDetailStatusEnum> get values => _$refundBatchDetailStatusEnumValues;
  static RefundBatchDetailStatusEnum valueOf(String name) => _$refundBatchDetailStatusEnumValueOf(name);
}

