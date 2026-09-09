//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_payout_batch_status_request.g.dart';

/// SetPayoutBatchStatusRequest
///
/// Properties:
/// * [status] - The step to record. `voided` is refused here (400) — voiding must also un-mark every item and carry a reason, so it has its own endpoint; `generated` is only ever the initial state. 
/// * [note] - Free text kept with the change (e.g. the bank's rejection message).
@BuiltValue()
abstract class SetPayoutBatchStatusRequest implements Built<SetPayoutBatchStatusRequest, SetPayoutBatchStatusRequestBuilder> {
  /// The step to record. `voided` is refused here (400) — voiding must also un-mark every item and carry a reason, so it has its own endpoint; `generated` is only ever the initial state. 
  @BuiltValueField(wireName: r'status')
  SetPayoutBatchStatusRequestStatusEnum get status;
  // enum statusEnum {  uploaded,  confirmed,  rejected,  };

  /// Free text kept with the change (e.g. the bank's rejection message).
  @BuiltValueField(wireName: r'note')
  String? get note;

  SetPayoutBatchStatusRequest._();

  factory SetPayoutBatchStatusRequest([void updates(SetPayoutBatchStatusRequestBuilder b)]) = _$SetPayoutBatchStatusRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetPayoutBatchStatusRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetPayoutBatchStatusRequest> get serializer => _$SetPayoutBatchStatusRequestSerializer();
}

class _$SetPayoutBatchStatusRequestSerializer implements PrimitiveSerializer<SetPayoutBatchStatusRequest> {
  @override
  final Iterable<Type> types = const [SetPayoutBatchStatusRequest, _$SetPayoutBatchStatusRequest];

  @override
  final String wireName = r'SetPayoutBatchStatusRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetPayoutBatchStatusRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(SetPayoutBatchStatusRequestStatusEnum),
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
    SetPayoutBatchStatusRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetPayoutBatchStatusRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SetPayoutBatchStatusRequestStatusEnum),
          ) as SetPayoutBatchStatusRequestStatusEnum;
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
  SetPayoutBatchStatusRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetPayoutBatchStatusRequestBuilder();
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

class SetPayoutBatchStatusRequestStatusEnum extends EnumClass {

  /// The step to record. `voided` is refused here (400) — voiding must also un-mark every item and carry a reason, so it has its own endpoint; `generated` is only ever the initial state. 
  @BuiltValueEnumConst(wireName: r'uploaded')
  static const SetPayoutBatchStatusRequestStatusEnum uploaded = _$setPayoutBatchStatusRequestStatusEnum_uploaded;
  /// The step to record. `voided` is refused here (400) — voiding must also un-mark every item and carry a reason, so it has its own endpoint; `generated` is only ever the initial state. 
  @BuiltValueEnumConst(wireName: r'confirmed')
  static const SetPayoutBatchStatusRequestStatusEnum confirmed = _$setPayoutBatchStatusRequestStatusEnum_confirmed;
  /// The step to record. `voided` is refused here (400) — voiding must also un-mark every item and carry a reason, so it has its own endpoint; `generated` is only ever the initial state. 
  @BuiltValueEnumConst(wireName: r'rejected')
  static const SetPayoutBatchStatusRequestStatusEnum rejected = _$setPayoutBatchStatusRequestStatusEnum_rejected;

  static Serializer<SetPayoutBatchStatusRequestStatusEnum> get serializer => _$setPayoutBatchStatusRequestStatusEnumSerializer;

  const SetPayoutBatchStatusRequestStatusEnum._(String name): super(name);

  static BuiltSet<SetPayoutBatchStatusRequestStatusEnum> get values => _$setPayoutBatchStatusRequestStatusEnumValues;
  static SetPayoutBatchStatusRequestStatusEnum valueOf(String name) => _$setPayoutBatchStatusRequestStatusEnumValueOf(name);
}

