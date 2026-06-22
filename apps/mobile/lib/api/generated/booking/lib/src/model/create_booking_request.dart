//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_booking_request.g.dart';

/// CreateBookingRequest
///
/// Properties:
/// * [address] 
/// * [scheduledAt] 
/// * [hours] 
/// * [serviceId] - Optional catalog service the customer picked. When present, the booking's `base_fee` is resolved SERVER-SIDE from that ACTIVE catalog service (the client never sends a fee) and the service's `min_hours` floor is enforced (`hours` below it → 400). A missing/inactive `service_id` → 404. When absent, `base_fee` falls to the server-owned column default (back-compat).
/// * [guardCount] - Number of guards requested. Authoritative once persisted (used by the money path).
/// * [tip] - Optional up-front tip (exact decimal string); folded into the expected total.
/// * [lat] - Optional site latitude (must be paired with `lng`) — feeds open-job radius discovery.
/// * [lng] - Optional site longitude (must be paired with `lat`).
@BuiltValue()
abstract class CreateBookingRequest implements Built<CreateBookingRequest, CreateBookingRequestBuilder> {
  @BuiltValueField(wireName: r'address')
  String get address;

  @BuiltValueField(wireName: r'scheduled_at')
  DateTime get scheduledAt;

  @BuiltValueField(wireName: r'hours')
  int get hours;

  /// Optional catalog service the customer picked. When present, the booking's `base_fee` is resolved SERVER-SIDE from that ACTIVE catalog service (the client never sends a fee) and the service's `min_hours` floor is enforced (`hours` below it → 400). A missing/inactive `service_id` → 404. When absent, `base_fee` falls to the server-owned column default (back-compat).
  @BuiltValueField(wireName: r'service_id')
  String? get serviceId;

  /// Number of guards requested. Authoritative once persisted (used by the money path).
  @BuiltValueField(wireName: r'guard_count')
  int? get guardCount;

  /// Optional up-front tip (exact decimal string); folded into the expected total.
  @BuiltValueField(wireName: r'tip')
  String? get tip;

  /// Optional site latitude (must be paired with `lng`) — feeds open-job radius discovery.
  @BuiltValueField(wireName: r'lat')
  double? get lat;

  /// Optional site longitude (must be paired with `lat`).
  @BuiltValueField(wireName: r'lng')
  double? get lng;

  CreateBookingRequest._();

  factory CreateBookingRequest([void updates(CreateBookingRequestBuilder b)]) = _$CreateBookingRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateBookingRequestBuilder b) => b
      ..guardCount = 1
      ..tip = '0';

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateBookingRequest> get serializer => _$CreateBookingRequestSerializer();
}

class _$CreateBookingRequestSerializer implements PrimitiveSerializer<CreateBookingRequest> {
  @override
  final Iterable<Type> types = const [CreateBookingRequest, _$CreateBookingRequest];

  @override
  final String wireName = r'CreateBookingRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    if (object.serviceId != null) {
      yield r'service_id';
      yield serializers.serialize(
        object.serviceId,
        specifiedType: const FullType(String),
      );
    }
    if (object.guardCount != null) {
      yield r'guard_count';
      yield serializers.serialize(
        object.guardCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.tip != null) {
      yield r'tip';
      yield serializers.serialize(
        object.tip,
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
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateBookingRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'service_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceId = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateBookingRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateBookingRequestBuilder();
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

