//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_booking_api/src/model/booking_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'internal_booking.g.dart';

/// The authoritative subset exposed to internal (service-JWT'd) callers — the fields the payment service needs to verify a charge, compute the expected total (`base_fee × hours × guard_count + tip`), and carry the guard into the payment event. Deliberately narrower than `Booking` (no address/timestamps). `base_fee` is server-owned — the client never sets it. 
///
/// Properties:
/// * [id] 
/// * [customerId] 
/// * [guardId] 
/// * [status] 
/// * [hours] 
/// * [baseFee] - Server-owned ฿/hour/guard rate (exact decimal)
/// * [guardCount] 
/// * [tip] - Up-front tip (exact decimal)
@BuiltValue()
abstract class InternalBooking implements Built<InternalBooking, InternalBookingBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'customer_id')
  String get customerId;

  @BuiltValueField(wireName: r'guard_id')
  String? get guardId;

  @BuiltValueField(wireName: r'status')
  BookingStatus get status;
  // enum statusEnum {  requested,  accepted,  declined,  en_route,  arrived,  pending_completion,  completed,  cancelled,  };

  @BuiltValueField(wireName: r'hours')
  int get hours;

  /// Server-owned ฿/hour/guard rate (exact decimal)
  @BuiltValueField(wireName: r'base_fee')
  String get baseFee;

  @BuiltValueField(wireName: r'guard_count')
  int get guardCount;

  /// Up-front tip (exact decimal)
  @BuiltValueField(wireName: r'tip')
  String get tip;

  InternalBooking._();

  factory InternalBooking([void updates(InternalBookingBuilder b)]) = _$InternalBooking;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InternalBookingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InternalBooking> get serializer => _$InternalBookingSerializer();
}

class _$InternalBookingSerializer implements PrimitiveSerializer<InternalBooking> {
  @override
  final Iterable<Type> types = const [InternalBooking, _$InternalBooking];

  @override
  final String wireName = r'InternalBooking';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InternalBooking object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'customer_id';
    yield serializers.serialize(
      object.customerId,
      specifiedType: const FullType(String),
    );
    if (object.guardId != null) {
      yield r'guard_id';
      yield serializers.serialize(
        object.guardId,
        specifiedType: const FullType(String),
      );
    }
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(BookingStatus),
    );
    yield r'hours';
    yield serializers.serialize(
      object.hours,
      specifiedType: const FullType(int),
    );
    yield r'base_fee';
    yield serializers.serialize(
      object.baseFee,
      specifiedType: const FullType(String),
    );
    yield r'guard_count';
    yield serializers.serialize(
      object.guardCount,
      specifiedType: const FullType(int),
    );
    yield r'tip';
    yield serializers.serialize(
      object.tip,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    InternalBooking object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InternalBookingBuilder result,
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
        case r'customer_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.customerId = valueDes;
          break;
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BookingStatus),
          ) as BookingStatus;
          result.status = valueDes;
          break;
        case r'hours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.hours = valueDes;
          break;
        case r'base_fee':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.baseFee = valueDes;
          break;
        case r'guard_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.guardCount = valueDes;
          break;
        case r'tip':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.tip = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InternalBooking deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InternalBookingBuilder();
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

