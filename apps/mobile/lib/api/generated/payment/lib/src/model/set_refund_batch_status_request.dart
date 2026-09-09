//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_refund_batch_status_request.g.dart';

/// SetRefundBatchStatusRequest
///
/// Properties:
/// * [status] - The step to record. `voided` is refused here (400) — voiding must also un-mark every item, return its source row to `pending`, and carry a reason, so it has its own endpoint; `generated` is only ever the initial state. 
/// * [note] - Free text kept with the change (e.g. the bank's rejection message).
@BuiltValue()
abstract class SetRefundBatchStatusRequest implements Built<SetRefundBatchStatusRequest, SetRefundBatchStatusRequestBuilder> {
  /// The step to record. `voided` is refused here (400) — voiding must also un-mark every item, return its source row to `pending`, and carry a reason, so it has its own endpoint; `generated` is only ever the initial state. 
  @BuiltValueField(wireName: r'status')
  SetRefundBatchStatusRequestStatusEnum get status;
  // enum statusEnum {  uploaded,  confirmed,  rejected,  };

  /// Free text kept with the change (e.g. the bank's rejection message).
  @BuiltValueField(wireName: r'note')
  String? get note;

  SetRefundBatchStatusRequest._();

  factory SetRefundBatchStatusRequest([void updates(SetRefundBatchStatusRequestBuilder b)]) = _$SetRefundBatchStatusRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetRefundBatchStatusRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetRefundBatchStatusRequest> get serializer => _$SetRefundBatchStatusRequestSerializer();
}

class _$SetRefundBatchStatusRequestSerializer implements PrimitiveSerializer<SetRefundBatchStatusRequest> {
  @override
  final Iterable<Type> types = const [SetRefundBatchStatusRequest, _$SetRefundBatchStatusRequest];

  @override
  final String wireName = r'SetRefundBatchStatusRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetRefundBatchStatusRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(SetRefundBatchStatusRequestStatusEnum),
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
    SetRefundBatchStatusRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetRefundBatchStatusRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SetRefundBatchStatusRequestStatusEnum),
          ) as SetRefundBatchStatusRequestStatusEnum;
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
  SetRefundBatchStatusRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetRefundBatchStatusRequestBuilder();
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

class SetRefundBatchStatusRequestStatusEnum extends EnumClass {

  /// The step to record. `voided` is refused here (400) — voiding must also un-mark every item, return its source row to `pending`, and carry a reason, so it has its own endpoint; `generated` is only ever the initial state. 
  @BuiltValueEnumConst(wireName: r'uploaded')
  static const SetRefundBatchStatusRequestStatusEnum uploaded = _$setRefundBatchStatusRequestStatusEnum_uploaded;
  /// The step to record. `voided` is refused here (400) — voiding must also un-mark every item, return its source row to `pending`, and carry a reason, so it has its own endpoint; `generated` is only ever the initial state. 
  @BuiltValueEnumConst(wireName: r'confirmed')
  static const SetRefundBatchStatusRequestStatusEnum confirmed = _$setRefundBatchStatusRequestStatusEnum_confirmed;
  /// The step to record. `voided` is refused here (400) — voiding must also un-mark every item, return its source row to `pending`, and carry a reason, so it has its own endpoint; `generated` is only ever the initial state. 
  @BuiltValueEnumConst(wireName: r'rejected')
  static const SetRefundBatchStatusRequestStatusEnum rejected = _$setRefundBatchStatusRequestStatusEnum_rejected;

  static Serializer<SetRefundBatchStatusRequestStatusEnum> get serializer => _$setRefundBatchStatusRequestStatusEnumSerializer;

  const SetRefundBatchStatusRequestStatusEnum._(String name): super(name);

  static BuiltSet<SetRefundBatchStatusRequestStatusEnum> get values => _$setRefundBatchStatusRequestStatusEnumValues;
  static SetRefundBatchStatusRequestStatusEnum valueOf(String name) => _$setRefundBatchStatusRequestStatusEnumValueOf(name);
}

