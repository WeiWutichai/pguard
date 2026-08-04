//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cancel_booking_request.g.dart';

/// Why the CUSTOMER is cancelling. Mandatory (`requestBody.required: true`) — the reason is an operational signal, not a nicety. `reason` is a STABLE CODE, never localized text: the client renders the Thai/English label and sends the code, so labels can be reworded without a data migration. Validation: an absent/unknown code → 400 `CANCEL_REASON_REQUIRED`; `other` without a note → 400 `CANCEL_NOTE_REQUIRED`. 
///
/// Properties:
/// * [reason] - Stable cancellation code (customer set): `changed_plan` เปลี่ยนแผน / Changed plans · `mistake` แจ้งผิดพลาด / Booked by mistake · `not_needed` ไม่ต้องการแล้ว / No longer needed · `other` อื่นๆ / Other (REQUIRES `note`). 
/// * [note] - Optional free-text detail (trimmed; empty treated as absent; max 500 characters). REQUIRED when `reason = other` — a blank one is 400 `CANCEL_NOTE_REQUIRED`.
@BuiltValue()
abstract class CancelBookingRequest implements Built<CancelBookingRequest, CancelBookingRequestBuilder> {
  /// Stable cancellation code (customer set): `changed_plan` เปลี่ยนแผน / Changed plans · `mistake` แจ้งผิดพลาด / Booked by mistake · `not_needed` ไม่ต้องการแล้ว / No longer needed · `other` อื่นๆ / Other (REQUIRES `note`). 
  @BuiltValueField(wireName: r'reason')
  CancelBookingRequestReasonEnum get reason;
  // enum reasonEnum {  changed_plan,  mistake,  not_needed,  other,  };

  /// Optional free-text detail (trimmed; empty treated as absent; max 500 characters). REQUIRED when `reason = other` — a blank one is 400 `CANCEL_NOTE_REQUIRED`.
  @BuiltValueField(wireName: r'note')
  String? get note;

  CancelBookingRequest._();

  factory CancelBookingRequest([void updates(CancelBookingRequestBuilder b)]) = _$CancelBookingRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CancelBookingRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CancelBookingRequest> get serializer => _$CancelBookingRequestSerializer();
}

class _$CancelBookingRequestSerializer implements PrimitiveSerializer<CancelBookingRequest> {
  @override
  final Iterable<Type> types = const [CancelBookingRequest, _$CancelBookingRequest];

  @override
  final String wireName = r'CancelBookingRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CancelBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(CancelBookingRequestReasonEnum),
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
    CancelBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CancelBookingRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CancelBookingRequestReasonEnum),
          ) as CancelBookingRequestReasonEnum;
          result.reason = valueDes;
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
  CancelBookingRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CancelBookingRequestBuilder();
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

class CancelBookingRequestReasonEnum extends EnumClass {

  /// Stable cancellation code (customer set): `changed_plan` เปลี่ยนแผน / Changed plans · `mistake` แจ้งผิดพลาด / Booked by mistake · `not_needed` ไม่ต้องการแล้ว / No longer needed · `other` อื่นๆ / Other (REQUIRES `note`). 
  @BuiltValueEnumConst(wireName: r'changed_plan')
  static const CancelBookingRequestReasonEnum changedPlan = _$cancelBookingRequestReasonEnum_changedPlan;
  /// Stable cancellation code (customer set): `changed_plan` เปลี่ยนแผน / Changed plans · `mistake` แจ้งผิดพลาด / Booked by mistake · `not_needed` ไม่ต้องการแล้ว / No longer needed · `other` อื่นๆ / Other (REQUIRES `note`). 
  @BuiltValueEnumConst(wireName: r'mistake')
  static const CancelBookingRequestReasonEnum mistake = _$cancelBookingRequestReasonEnum_mistake;
  /// Stable cancellation code (customer set): `changed_plan` เปลี่ยนแผน / Changed plans · `mistake` แจ้งผิดพลาด / Booked by mistake · `not_needed` ไม่ต้องการแล้ว / No longer needed · `other` อื่นๆ / Other (REQUIRES `note`). 
  @BuiltValueEnumConst(wireName: r'not_needed')
  static const CancelBookingRequestReasonEnum notNeeded = _$cancelBookingRequestReasonEnum_notNeeded;
  /// Stable cancellation code (customer set): `changed_plan` เปลี่ยนแผน / Changed plans · `mistake` แจ้งผิดพลาด / Booked by mistake · `not_needed` ไม่ต้องการแล้ว / No longer needed · `other` อื่นๆ / Other (REQUIRES `note`). 
  @BuiltValueEnumConst(wireName: r'other')
  static const CancelBookingRequestReasonEnum other = _$cancelBookingRequestReasonEnum_other;

  static Serializer<CancelBookingRequestReasonEnum> get serializer => _$cancelBookingRequestReasonEnumSerializer;

  const CancelBookingRequestReasonEnum._(String name): super(name);

  static BuiltSet<CancelBookingRequestReasonEnum> get values => _$cancelBookingRequestReasonEnumValues;
  static CancelBookingRequestReasonEnum valueOf(String name) => _$cancelBookingRequestReasonEnumValueOf(name);
}

