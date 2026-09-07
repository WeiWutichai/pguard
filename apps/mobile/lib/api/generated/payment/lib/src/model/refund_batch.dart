//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refund_batch.g.dart';

/// One generated SCB customer-refund file — the header only (the file text is its own endpoint). The lifecycle is `generated → uploaded → confirmed | rejected`, with `generated`/`uploaded`/`rejected` also able to go to `voided`; `confirmed` and `voided` are TERMINAL. 
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
@BuiltValue(instantiable: false)
abstract class RefundBatch  {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// HEADER field 1 = batch_ref || product code (e.g. `070926120000PPY`). NOT the download filename.
  @BuiltValueField(wireName: r'file_ref')
  String get fileRef;

  /// HEADER field 2 — `PGUARD-REFUND` (the payout file carries `PGUARD-PAYOUT`).
  @BuiltValueField(wireName: r'system_ref')
  String get systemRef;

  /// BCHDET field 1 — the bare 12-digit DDMMYYHHMMSS Bangkok stamp.
  @BuiltValueField(wireName: r'batch_ref')
  String get batchRef;

  @BuiltValueField(wireName: r'value_date')
  Date get valueDate;

  /// Σ transfers the file debits (2dp string).
  @BuiltValueField(wireName: r'total_amount')
  String get totalAmount;

  /// How many CUSTOMERS the file refunds (= TXNDET lines) — NOT how many obligations; a customer owed three refunds is one recipient.
  @BuiltValueField(wireName: r'recipient_count')
  int get recipientCount;

  @BuiltValueField(wireName: r'status')
  RefundBatchStatusEnum get status;
  // enum statusEnum {  generated,  uploaded,  confirmed,  rejected,  voided,  };

  /// Free text kept with the latest status change (typically the bank's own message).
  @BuiltValueField(wireName: r'status_note')
  String? get statusNote;

  @BuiltValueField(wireName: r'void_reason')
  String? get voidReason;

  /// Whether the file text is stored and can be re-downloaded.
  @BuiltValueField(wireName: r'has_file')
  bool get hasFile;

  @BuiltValueField(wireName: r'created_by')
  String? get createdBy;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'uploaded_at')
  DateTime? get uploadedAt;

  @BuiltValueField(wireName: r'confirmed_at')
  DateTime? get confirmedAt;

  @BuiltValueField(wireName: r'rejected_at')
  DateTime? get rejectedAt;

  @BuiltValueField(wireName: r'voided_at')
  DateTime? get voidedAt;

  @BuiltValueField(wireName: r'voided_by')
  String? get voidedBy;

  @BuiltValueSerializer(custom: true)
  static Serializer<RefundBatch> get serializer => _$RefundBatchSerializer();
}

class _$RefundBatchSerializer implements PrimitiveSerializer<RefundBatch> {
  @override
  final Iterable<Type> types = const [RefundBatch];

  @override
  final String wireName = r'RefundBatch';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RefundBatch object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'file_ref';
    yield serializers.serialize(
      object.fileRef,
      specifiedType: const FullType(String),
    );
    yield r'system_ref';
    yield serializers.serialize(
      object.systemRef,
      specifiedType: const FullType(String),
    );
    yield r'batch_ref';
    yield serializers.serialize(
      object.batchRef,
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
    yield r'recipient_count';
    yield serializers.serialize(
      object.recipientCount,
      specifiedType: const FullType(int),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(RefundBatchStatusEnum),
    );
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
    yield r'has_file';
    yield serializers.serialize(
      object.hasFile,
      specifiedType: const FullType(bool),
    );
    if (object.createdBy != null) {
      yield r'created_by';
      yield serializers.serialize(
        object.createdBy,
        specifiedType: const FullType(String),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.uploadedAt != null) {
      yield r'uploaded_at';
      yield serializers.serialize(
        object.uploadedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.confirmedAt != null) {
      yield r'confirmed_at';
      yield serializers.serialize(
        object.confirmedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.rejectedAt != null) {
      yield r'rejected_at';
      yield serializers.serialize(
        object.rejectedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.voidedAt != null) {
      yield r'voided_at';
      yield serializers.serialize(
        object.voidedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.voidedBy != null) {
      yield r'voided_by';
      yield serializers.serialize(
        object.voidedBy,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RefundBatch object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  RefundBatch deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($RefundBatch)) as $RefundBatch;
  }
}

/// a concrete implementation of [RefundBatch], since [RefundBatch] is not instantiable
@BuiltValue(instantiable: true)
abstract class $RefundBatch implements RefundBatch, Built<$RefundBatch, $RefundBatchBuilder> {
  $RefundBatch._();

  factory $RefundBatch([void Function($RefundBatchBuilder)? updates]) = _$$RefundBatch;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($RefundBatchBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$RefundBatch> get serializer => _$$RefundBatchSerializer();
}

class _$$RefundBatchSerializer implements PrimitiveSerializer<$RefundBatch> {
  @override
  final Iterable<Type> types = const [$RefundBatch, _$$RefundBatch];

  @override
  final String wireName = r'$RefundBatch';

  @override
  Object serialize(
    Serializers serializers,
    $RefundBatch object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(RefundBatch))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RefundBatchBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'file_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fileRef = valueDes;
          break;
        case r'system_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.systemRef = valueDes;
          break;
        case r'batch_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.batchRef = valueDes;
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
        case r'recipient_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.recipientCount = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RefundBatchStatusEnum),
          ) as RefundBatchStatusEnum;
          result.status = valueDes;
          break;
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
        case r'has_file':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasFile = valueDes;
          break;
        case r'created_by':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.createdBy = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'uploaded_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.uploadedAt = valueDes;
          break;
        case r'confirmed_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.confirmedAt = valueDes;
          break;
        case r'rejected_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.rejectedAt = valueDes;
          break;
        case r'voided_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.voidedAt = valueDes;
          break;
        case r'voided_by':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.voidedBy = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $RefundBatch deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $RefundBatchBuilder();
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

class RefundBatchStatusEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'generated')
  static const RefundBatchStatusEnum generated = _$refundBatchStatusEnum_generated;
  @BuiltValueEnumConst(wireName: r'uploaded')
  static const RefundBatchStatusEnum uploaded = _$refundBatchStatusEnum_uploaded;
  @BuiltValueEnumConst(wireName: r'confirmed')
  static const RefundBatchStatusEnum confirmed = _$refundBatchStatusEnum_confirmed;
  @BuiltValueEnumConst(wireName: r'rejected')
  static const RefundBatchStatusEnum rejected = _$refundBatchStatusEnum_rejected;
  @BuiltValueEnumConst(wireName: r'voided')
  static const RefundBatchStatusEnum voided = _$refundBatchStatusEnum_voided;

  static Serializer<RefundBatchStatusEnum> get serializer => _$refundBatchStatusEnumSerializer;

  const RefundBatchStatusEnum._(String name): super(name);

  static BuiltSet<RefundBatchStatusEnum> get values => _$refundBatchStatusEnumValues;
  static RefundBatchStatusEnum valueOf(String name) => _$refundBatchStatusEnumValueOf(name);
}

