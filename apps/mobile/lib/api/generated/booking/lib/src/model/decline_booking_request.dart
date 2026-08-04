//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'decline_booking_request.g.dart';

/// Why the ASSIGNED GUARD is withdrawing pre-arrival. Mandatory (`requestBody.required: true`); same code-not-text rule and the same `CANCEL_REASON_REQUIRED` / `CANCEL_NOTE_REQUIRED` validation as `CancelBookingRequest` — only the code set differs (guard reasons, not customer ones; sending a customer code here is 400 `CANCEL_REASON_REQUIRED`). 
///
/// Properties:
/// * [reason] - Stable withdrawal code (guard set): `emergency` เหตุฉุกเฉินส่วนตัว / Personal emergency · `sick` ป่วย / Sick · `cannot_reach` เดินทางไปไม่ได้ / Can't reach site · `other` อื่นๆ / Other (REQUIRES `note`). 
/// * [note] - Optional free-text detail (trimmed; empty treated as absent; max 500 characters). REQUIRED when `reason = other` — a blank one is 400 `CANCEL_NOTE_REQUIRED`.
@BuiltValue()
abstract class DeclineBookingRequest implements Built<DeclineBookingRequest, DeclineBookingRequestBuilder> {
  /// Stable withdrawal code (guard set): `emergency` เหตุฉุกเฉินส่วนตัว / Personal emergency · `sick` ป่วย / Sick · `cannot_reach` เดินทางไปไม่ได้ / Can't reach site · `other` อื่นๆ / Other (REQUIRES `note`). 
  @BuiltValueField(wireName: r'reason')
  DeclineBookingRequestReasonEnum get reason;
  // enum reasonEnum {  emergency,  sick,  cannot_reach,  other,  };

  /// Optional free-text detail (trimmed; empty treated as absent; max 500 characters). REQUIRED when `reason = other` — a blank one is 400 `CANCEL_NOTE_REQUIRED`.
  @BuiltValueField(wireName: r'note')
  String? get note;

  DeclineBookingRequest._();

  factory DeclineBookingRequest([void updates(DeclineBookingRequestBuilder b)]) = _$DeclineBookingRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeclineBookingRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeclineBookingRequest> get serializer => _$DeclineBookingRequestSerializer();
}

class _$DeclineBookingRequestSerializer implements PrimitiveSerializer<DeclineBookingRequest> {
  @override
  final Iterable<Type> types = const [DeclineBookingRequest, _$DeclineBookingRequest];

  @override
  final String wireName = r'DeclineBookingRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeclineBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(DeclineBookingRequestReasonEnum),
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
    DeclineBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeclineBookingRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DeclineBookingRequestReasonEnum),
          ) as DeclineBookingRequestReasonEnum;
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
  DeclineBookingRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeclineBookingRequestBuilder();
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

class DeclineBookingRequestReasonEnum extends EnumClass {

  /// Stable withdrawal code (guard set): `emergency` เหตุฉุกเฉินส่วนตัว / Personal emergency · `sick` ป่วย / Sick · `cannot_reach` เดินทางไปไม่ได้ / Can't reach site · `other` อื่นๆ / Other (REQUIRES `note`). 
  @BuiltValueEnumConst(wireName: r'emergency')
  static const DeclineBookingRequestReasonEnum emergency = _$declineBookingRequestReasonEnum_emergency;
  /// Stable withdrawal code (guard set): `emergency` เหตุฉุกเฉินส่วนตัว / Personal emergency · `sick` ป่วย / Sick · `cannot_reach` เดินทางไปไม่ได้ / Can't reach site · `other` อื่นๆ / Other (REQUIRES `note`). 
  @BuiltValueEnumConst(wireName: r'sick')
  static const DeclineBookingRequestReasonEnum sick = _$declineBookingRequestReasonEnum_sick;
  /// Stable withdrawal code (guard set): `emergency` เหตุฉุกเฉินส่วนตัว / Personal emergency · `sick` ป่วย / Sick · `cannot_reach` เดินทางไปไม่ได้ / Can't reach site · `other` อื่นๆ / Other (REQUIRES `note`). 
  @BuiltValueEnumConst(wireName: r'cannot_reach')
  static const DeclineBookingRequestReasonEnum cannotReach = _$declineBookingRequestReasonEnum_cannotReach;
  /// Stable withdrawal code (guard set): `emergency` เหตุฉุกเฉินส่วนตัว / Personal emergency · `sick` ป่วย / Sick · `cannot_reach` เดินทางไปไม่ได้ / Can't reach site · `other` อื่นๆ / Other (REQUIRES `note`). 
  @BuiltValueEnumConst(wireName: r'other')
  static const DeclineBookingRequestReasonEnum other = _$declineBookingRequestReasonEnum_other;

  static Serializer<DeclineBookingRequestReasonEnum> get serializer => _$declineBookingRequestReasonEnumSerializer;

  const DeclineBookingRequestReasonEnum._(String name): super(name);

  static BuiltSet<DeclineBookingRequestReasonEnum> get values => _$declineBookingRequestReasonEnumValues;
  static DeclineBookingRequestReasonEnum valueOf(String name) => _$declineBookingRequestReasonEnumValueOf(name);
}

