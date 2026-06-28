//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_booking_api/src/model/booking_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking.g.dart';

/// Booking
///
/// Properties:
/// * [id] 
/// * [customerId] 
/// * [guardId] 
/// * [status] 
/// * [address] 
/// * [scheduledAt] 
/// * [hours] 
/// * [baseFee] - Server-owned ฿/hour/guard rate (exact decimal)
/// * [guardCount] 
/// * [tip] - Up-front tip (exact decimal)
/// * [serviceId] - The catalog service this booking was placed against (the service-type dimension). null for bookings created without picking a catalog service. Set server-side from the request's `service_id` (the same id that resolved `base_fee`).
/// * [lat] - Site latitude (null when not provided at create).
/// * [lng] - Site longitude (null when not provided at create).
/// * [paidAt] - When the PRE-PAY charge cleared (stamped by the payment.completed consumer). null = unpaid; the client uses this to know the accepted→en_route transition is gated (show the pay-step).
/// * [createdAt] 
/// * [updatedAt] 
@BuiltValue()
abstract class Booking implements Built<Booking, BookingBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'customer_id')
  String get customerId;

  @BuiltValueField(wireName: r'guard_id')
  String? get guardId;

  @BuiltValueField(wireName: r'status')
  BookingStatus get status;
  // enum statusEnum {  requested,  accepted,  declined,  en_route,  arrived,  pending_completion,  completed,  cancelled,  };

  @BuiltValueField(wireName: r'address')
  String get address;

  @BuiltValueField(wireName: r'scheduled_at')
  DateTime get scheduledAt;

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

  /// The catalog service this booking was placed against (the service-type dimension). null for bookings created without picking a catalog service. Set server-side from the request's `service_id` (the same id that resolved `base_fee`).
  @BuiltValueField(wireName: r'service_id')
  String? get serviceId;

  /// Site latitude (null when not provided at create).
  @BuiltValueField(wireName: r'lat')
  double? get lat;

  /// Site longitude (null when not provided at create).
  @BuiltValueField(wireName: r'lng')
  double? get lng;

  /// When the PRE-PAY charge cleared (stamped by the payment.completed consumer). null = unpaid; the client uses this to know the accepted→en_route transition is gated (show the pay-step).
  @BuiltValueField(wireName: r'paid_at')
  DateTime? get paidAt;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  Booking._();

  factory Booking([void updates(BookingBuilder b)]) = _$Booking;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Booking> get serializer => _$BookingSerializer();
}

class _$BookingSerializer implements PrimitiveSerializer<Booking> {
  @override
  final Iterable<Type> types = const [Booking, _$Booking];

  @override
  final String wireName = r'Booking';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Booking object, {
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
    yield r'address';
    yield serializers.serialize(
      object.address,
      specifiedType: const FullType(String),
    );
    yield r'scheduled_at';
    yield serializers.serialize(
      object.scheduledAt,
      specifiedType: const FullType(DateTime),
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
    if (object.serviceId != null) {
      yield r'service_id';
      yield serializers.serialize(
        object.serviceId,
        specifiedType: const FullType(String),
      );
    }
    if (object.lat != null) {
      yield r'lat';
      yield serializers.serialize(
        object.lat,
        specifiedType: const FullType(double),
      );
    }
    if (object.lng != null) {
      yield r'lng';
      yield serializers.serialize(
        object.lng,
        specifiedType: const FullType(double),
      );
    }
    if (object.paidAt != null) {
      yield r'paid_at';
      yield serializers.serialize(
        object.paidAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'updated_at';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Booking object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookingBuilder result,
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
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        case r'scheduled_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.scheduledAt = valueDes;
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
        case r'service_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceId = valueDes;
          break;
        case r'lat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.lat = valueDes;
          break;
        case r'lng':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.lng = valueDes;
          break;
        case r'paid_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.paidAt = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Booking deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingBuilder();
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

