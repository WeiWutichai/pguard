//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_deduction_batch_status_request.g.dart';

/// SetDeductionBatchStatusRequest
///
/// Properties:
/// * [status] - `voided` is refused here (400) — it must release every job and carry a reason, so it has its own endpoint.
/// * [note] - Optional free text kept with the change (typically the bank's own rejection message). Max 500 characters.
@BuiltValue()
abstract class SetDeductionBatchStatusRequest implements Built<SetDeductionBatchStatusRequest, SetDeductionBatchStatusRequestBuilder> {
  /// `voided` is refused here (400) — it must release every job and carry a reason, so it has its own endpoint.
  @BuiltValueField(wireName: r'status')
  SetDeductionBatchStatusRequestStatusEnum get status;
  // enum statusEnum {  uploaded,  confirmed,  rejected,  };

  /// Optional free text kept with the change (typically the bank's own rejection message). Max 500 characters.
  @BuiltValueField(wireName: r'note')
  String? get note;

  SetDeductionBatchStatusRequest._();

  factory SetDeductionBatchStatusRequest([void updates(SetDeductionBatchStatusRequestBuilder b)]) = _$SetDeductionBatchStatusRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetDeductionBatchStatusRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetDeductionBatchStatusRequest> get serializer => _$SetDeductionBatchStatusRequestSerializer();
}

class _$SetDeductionBatchStatusRequestSerializer implements PrimitiveSerializer<SetDeductionBatchStatusRequest> {
  @override
  final Iterable<Type> types = const [SetDeductionBatchStatusRequest, _$SetDeductionBatchStatusRequest];

  @override
  final String wireName = r'SetDeductionBatchStatusRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetDeductionBatchStatusRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(SetDeductionBatchStatusRequestStatusEnum),
    );
    if (object.note != null) {
      yield r'note';
      yield serializers.serialize(
        object.note,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SetDeductionBatchStatusRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetDeductionBatchStatusRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SetDeductionBatchStatusRequestStatusEnum),
          ) as SetDeductionBatchStatusRequestStatusEnum;
          result.status = valueDes;
          break;
        case r'note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.note = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SetDeductionBatchStatusRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetDeductionBatchStatusRequestBuilder();
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

class SetDeductionBatchStatusRequestStatusEnum extends EnumClass {

  /// `voided` is refused here (400) — it must release every job and carry a reason, so it has its own endpoint.
  @BuiltValueEnumConst(wireName: r'uploaded')
  static const SetDeductionBatchStatusRequestStatusEnum uploaded = _$setDeductionBatchStatusRequestStatusEnum_uploaded;
  /// `voided` is refused here (400) — it must release every job and carry a reason, so it has its own endpoint.
  @BuiltValueEnumConst(wireName: r'confirmed')
  static const SetDeductionBatchStatusRequestStatusEnum confirmed = _$setDeductionBatchStatusRequestStatusEnum_confirmed;
  /// `voided` is refused here (400) — it must release every job and carry a reason, so it has its own endpoint.
  @BuiltValueEnumConst(wireName: r'rejected')
  static const SetDeductionBatchStatusRequestStatusEnum rejected = _$setDeductionBatchStatusRequestStatusEnum_rejected;

  static Serializer<SetDeductionBatchStatusRequestStatusEnum> get serializer => _$setDeductionBatchStatusRequestStatusEnumSerializer;

  const SetDeductionBatchStatusRequestStatusEnum._(String name): super(name);

  static BuiltSet<SetDeductionBatchStatusRequestStatusEnum> get values => _$setDeductionBatchStatusRequestStatusEnumValues;
  static SetDeductionBatchStatusRequestStatusEnum valueOf(String name) => _$setDeductionBatchStatusRequestStatusEnumValueOf(name);
}

