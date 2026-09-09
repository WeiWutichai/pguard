//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'payout_batch.g.dart';

/// One generated SCB payout file — the header only (the file text is its own endpoint). The lifecycle is `generated → uploaded → confirmed | rejected`, with `generated`/`uploaded`/`rejected` also able to go to `voided`; `confirmed` and `voided` are TERMINAL. 
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
@BuiltValue(instantiable: false)
abstract class PayoutBatch  {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// HEADER field 1 = batch_ref || product code (e.g. `050926120000PPY`). NOT the download filename.
  @BuiltValueField(wireName: r'file_ref')
  String get fileRef;

  @BuiltValueField(wireName: r'system_ref')
  String get systemRef;

  /// BCHDET field 1 — the bare 12-digit DDMMYYHHMMSS Bangkok stamp.
  @BuiltValueField(wireName: r'batch_ref')
  String get batchRef;

  @BuiltValueField(wireName: r'value_date')
  Date get valueDate;

  /// Σ net transfers the file debits (2dp string).
  @BuiltValueField(wireName: r'total_amount')
  String get totalAmount;

  /// How many GUARDS the file pays (= TXNDET lines) — NOT how many bookings; a guard with three finished jobs is one recipient.
  @BuiltValueField(wireName: r'recipient_count')
  int get recipientCount;

  @BuiltValueField(wireName: r'status')
  PayoutBatchStatusEnum get status;
  // enum statusEnum {  generated,  uploaded,  confirmed,  rejected,  voided,  };

  /// Free text kept with the latest status change (typically the bank's own message).
  @BuiltValueField(wireName: r'status_note')
  String? get statusNote;

  @BuiltValueField(wireName: r'void_reason')
  String? get voidReason;

  /// Whether the file text is stored and can be re-downloaded (false for batches generated before the text was kept).
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
  static Serializer<PayoutBatch> get serializer => _$PayoutBatchSerializer();
}

class _$PayoutBatchSerializer implements PrimitiveSerializer<PayoutBatch> {
  @override
  final Iterable<Type> types = const [PayoutBatch];

  @override
  final String wireName = r'PayoutBatch';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PayoutBatch object, {
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
      specifiedType: const FullType(PayoutBatchStatusEnum),
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
    PayoutBatch object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  PayoutBatch deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($PayoutBatch)) as $PayoutBatch;
  }
}

/// a concrete implementation of [PayoutBatch], since [PayoutBatch] is not instantiable
@BuiltValue(instantiable: true)
abstract class $PayoutBatch implements PayoutBatch, Built<$PayoutBatch, $PayoutBatchBuilder> {
  $PayoutBatch._();

  factory $PayoutBatch([void Function($PayoutBatchBuilder)? updates]) = _$$PayoutBatch;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($PayoutBatchBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$PayoutBatch> get serializer => _$$PayoutBatchSerializer();
}

class _$$PayoutBatchSerializer implements PrimitiveSerializer<$PayoutBatch> {
  @override
  final Iterable<Type> types = const [$PayoutBatch, _$$PayoutBatch];

  @override
  final String wireName = r'$PayoutBatch';

  @override
  Object serialize(
    Serializers serializers,
    $PayoutBatch object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(PayoutBatch))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PayoutBatchBuilder result,
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
            specifiedType: const FullType(PayoutBatchStatusEnum),
          ) as PayoutBatchStatusEnum;
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
  $PayoutBatch deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $PayoutBatchBuilder();
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

class PayoutBatchStatusEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'generated')
  static const PayoutBatchStatusEnum generated = _$payoutBatchStatusEnum_generated;
  @BuiltValueEnumConst(wireName: r'uploaded')
  static const PayoutBatchStatusEnum uploaded = _$payoutBatchStatusEnum_uploaded;
  @BuiltValueEnumConst(wireName: r'confirmed')
  static const PayoutBatchStatusEnum confirmed = _$payoutBatchStatusEnum_confirmed;
  @BuiltValueEnumConst(wireName: r'rejected')
  static const PayoutBatchStatusEnum rejected = _$payoutBatchStatusEnum_rejected;
  @BuiltValueEnumConst(wireName: r'voided')
  static const PayoutBatchStatusEnum voided = _$payoutBatchStatusEnum_voided;

  static Serializer<PayoutBatchStatusEnum> get serializer => _$payoutBatchStatusEnumSerializer;

  const PayoutBatchStatusEnum._(String name): super(name);

  static BuiltSet<PayoutBatchStatusEnum> get values => _$payoutBatchStatusEnumValues;
  static PayoutBatchStatusEnum valueOf(String name) => _$payoutBatchStatusEnumValueOf(name);
}

