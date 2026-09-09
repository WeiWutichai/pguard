//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/deduction_batch_item.dart';
import 'package:pguard_payment_api/src/model/deduction_batch.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'deduction_batch_detail.g.dart';

/// DeductionBatchDetail
///
/// Properties:
/// * [id] 
/// * [fileRef] - `HEADER` field 1 = batch_ref || `OAT`. NOT the download filename.
/// * [systemRef] 
/// * [batchRef] - `BCHDET` field 1 — the bare 12-digit DDMMYYHHMMSS Bangkok stamp.
/// * [valueDate] 
/// * [totalAmount] - Σ of every job's cut — and, because an OAT batch credits one destination, also the single TXNDET amount.
/// * [creditAccount] - The company account this file credited
/// * [recipientCount] - Always 1 — an OAT batch credits ONE destination. `job_count` is the number that means something here.
/// * [jobCount] - How many jobs' cuts this sweep collected.
/// * [status] - Lifecycle: `generated → uploaded → confirmed | rejected`; `generated`/`uploaded`/`rejected` → `voided`. `confirmed` and `voided` are TERMINAL — the same table the payout and refund files walk. 
/// * [statusNote] 
/// * [voidReason] 
/// * [hasFile] - Whether the stored text exists
/// * [createdBy] 
/// * [createdAt] 
/// * [uploadedAt] 
/// * [confirmedAt] 
/// * [rejectedAt] 
/// * [voidedAt] 
/// * [voidedBy] 
/// * [items] 
@BuiltValue()
abstract class DeductionBatchDetail implements DeductionBatch, Built<DeductionBatchDetail, DeductionBatchDetailBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<DeductionBatchItem> get items;

  DeductionBatchDetail._();

  factory DeductionBatchDetail([void updates(DeductionBatchDetailBuilder b)]) = _$DeductionBatchDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeductionBatchDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeductionBatchDetail> get serializer => _$DeductionBatchDetailSerializer();
}

class _$DeductionBatchDetailSerializer implements PrimitiveSerializer<DeductionBatchDetail> {
  @override
  final Iterable<Type> types = const [DeductionBatchDetail, _$DeductionBatchDetail];

  @override
  final String wireName = r'DeductionBatchDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeductionBatchDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.statusNote != null) {
      yield r'status_note';
      yield serializers.serialize(
        object.statusNote,
        specifiedType: const FullType(String),
      );
    }
    yield r'credit_account';
    yield serializers.serialize(
      object.creditAccount,
      specifiedType: const FullType(String),
    );
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
      specifiedType: const FullType(BuiltList, [FullType(DeductionBatchItem)]),
    );
    yield r'job_count';
    yield serializers.serialize(
      object.jobCount,
      specifiedType: const FullType(int),
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
      specifiedType: const FullType(DeductionBatchStatusEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DeductionBatchDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeductionBatchDetailBuilder result,
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
        case r'credit_account':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.creditAccount = valueDes;
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
            specifiedType: const FullType(BuiltList, [FullType(DeductionBatchItem)]),
          ) as BuiltList<DeductionBatchItem>;
          result.items.replace(valueDes);
          break;
        case r'job_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.jobCount = valueDes;
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
            specifiedType: const FullType(DeductionBatchStatusEnum),
          ) as DeductionBatchStatusEnum;
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
  DeductionBatchDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeductionBatchDetailBuilder();
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

class DeductionBatchDetailStatusEnum extends EnumClass {

  /// Lifecycle: `generated → uploaded → confirmed | rejected`; `generated`/`uploaded`/`rejected` → `voided`. `confirmed` and `voided` are TERMINAL — the same table the payout and refund files walk. 
  @BuiltValueEnumConst(wireName: r'generated')
  static const DeductionBatchDetailStatusEnum generated = _$deductionBatchDetailStatusEnum_generated;
  /// Lifecycle: `generated → uploaded → confirmed | rejected`; `generated`/`uploaded`/`rejected` → `voided`. `confirmed` and `voided` are TERMINAL — the same table the payout and refund files walk. 
  @BuiltValueEnumConst(wireName: r'uploaded')
  static const DeductionBatchDetailStatusEnum uploaded = _$deductionBatchDetailStatusEnum_uploaded;
  /// Lifecycle: `generated → uploaded → confirmed | rejected`; `generated`/`uploaded`/`rejected` → `voided`. `confirmed` and `voided` are TERMINAL — the same table the payout and refund files walk. 
  @BuiltValueEnumConst(wireName: r'confirmed')
  static const DeductionBatchDetailStatusEnum confirmed = _$deductionBatchDetailStatusEnum_confirmed;
  /// Lifecycle: `generated → uploaded → confirmed | rejected`; `generated`/`uploaded`/`rejected` → `voided`. `confirmed` and `voided` are TERMINAL — the same table the payout and refund files walk. 
  @BuiltValueEnumConst(wireName: r'rejected')
  static const DeductionBatchDetailStatusEnum rejected = _$deductionBatchDetailStatusEnum_rejected;
  /// Lifecycle: `generated → uploaded → confirmed | rejected`; `generated`/`uploaded`/`rejected` → `voided`. `confirmed` and `voided` are TERMINAL — the same table the payout and refund files walk. 
  @BuiltValueEnumConst(wireName: r'voided')
  static const DeductionBatchDetailStatusEnum voided = _$deductionBatchDetailStatusEnum_voided;

  static Serializer<DeductionBatchDetailStatusEnum> get serializer => _$deductionBatchDetailStatusEnumSerializer;

  const DeductionBatchDetailStatusEnum._(String name): super(name);

  static BuiltSet<DeductionBatchDetailStatusEnum> get values => _$deductionBatchDetailStatusEnumValues;
  static DeductionBatchDetailStatusEnum valueOf(String name) => _$deductionBatchDetailStatusEnumValueOf(name);
}

