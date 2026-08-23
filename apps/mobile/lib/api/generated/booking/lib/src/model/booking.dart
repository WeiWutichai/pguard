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
/// * [baseFee] - Server-owned VAT-EXCLUSIVE ฿/hour/guard rate (exact decimal). VAT 7% is added on the payment, not here.
/// * [guardCount] 
/// * [tip] - Up-front tip (exact decimal, VAT-exclusive like base_fee)
/// * [commissionPercent] - SNAPSHOT of the catalog's commission percent (0–100, exact decimal string) taken when this booking was created, so a later catalog edit never rewrites the money of a job already booked. Deducted from the GUARD's pay only — the customer's bill is identical with or without it. null on bookings created before the feature existed → treat as 0.
/// * [cancellationFee] - SNAPSHOT of the catalog's cancellation fee (฿, exact decimal string, ≥ 0) taken at creation. Charged to the CUSTOMER only when the CUSTOMER cancels before work starts, and only up to what was actually paid; a guard withdrawal is still a full refund. What was really kept is the payment's `cancellation_fee_charged`. null on pre-feature bookings → treat as 0.
/// * [lat] - Site latitude (null when not provided at create).
/// * [lng] - Site longitude (null when not provided at create).
/// * [targetGuardId] - DIRECTED OFFER (C3): the ONE guard this booking was OFFERED to at create — DISTINCT from `guard_id` (the guard who ACCEPTED). null = OPEN first-come (legacy rows and un-directed bookings): any online guard may claim it. When set, discovery hides the booking from every other guard and `accept` 403s a non-target `NOT_OFFERED_TO_YOU`. On a directed booking the target accepts, this and `guard_id` end up the same guard.
/// * [workStartedAt] - When the assigned guard STARTED work (stamped by PUT /bookings/{id}/start; the proration basis). null until started — clients restore the job clock from this after an app restart.
/// * [paidAt] - When the PRE-PAY charge cleared (stamped by the payment.completed consumer). null = unpaid; the client uses this to know the accepted→en_route transition is gated (show the pay-step).
/// * [cancellationReason] - Why the booking ended early — the stable code supplied to cancel (`changed_plan`|`mistake`|`not_needed`|`other`) or decline (`emergency`|`sick`|`cannot_reach`|`other`); see `CancelBookingRequest` / `DeclineBookingRequest` for the labels. NEVER localized text: clients map the code to a label. Deliberately typed as a plain string, not an enum, so an unrecognized code degrades to \"ไม่ระบุ\"/\"Not specified\" instead of failing response decoding. null on active bookings, and on terminal rows created BEFORE the reason became mandatory (migration 0009).
/// * [cancellationNote] - The optional free-text detail that came with `cancellation_reason` (trimmed, ≤ 500 characters). null when none was given; always present when the reason is `other`.
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

  /// Server-owned VAT-EXCLUSIVE ฿/hour/guard rate (exact decimal). VAT 7% is added on the payment, not here.
  @BuiltValueField(wireName: r'base_fee')
  String get baseFee;

  @BuiltValueField(wireName: r'guard_count')
  int get guardCount;

  /// Up-front tip (exact decimal, VAT-exclusive like base_fee)
  @BuiltValueField(wireName: r'tip')
  String get tip;

  /// SNAPSHOT of the catalog's commission percent (0–100, exact decimal string) taken when this booking was created, so a later catalog edit never rewrites the money of a job already booked. Deducted from the GUARD's pay only — the customer's bill is identical with or without it. null on bookings created before the feature existed → treat as 0.
  @BuiltValueField(wireName: r'commission_percent')
  String? get commissionPercent;

  /// SNAPSHOT of the catalog's cancellation fee (฿, exact decimal string, ≥ 0) taken at creation. Charged to the CUSTOMER only when the CUSTOMER cancels before work starts, and only up to what was actually paid; a guard withdrawal is still a full refund. What was really kept is the payment's `cancellation_fee_charged`. null on pre-feature bookings → treat as 0.
  @BuiltValueField(wireName: r'cancellation_fee')
  String? get cancellationFee;

  /// Site latitude (null when not provided at create).
  @BuiltValueField(wireName: r'lat')
  double? get lat;

  /// Site longitude (null when not provided at create).
  @BuiltValueField(wireName: r'lng')
  double? get lng;

  /// DIRECTED OFFER (C3): the ONE guard this booking was OFFERED to at create — DISTINCT from `guard_id` (the guard who ACCEPTED). null = OPEN first-come (legacy rows and un-directed bookings): any online guard may claim it. When set, discovery hides the booking from every other guard and `accept` 403s a non-target `NOT_OFFERED_TO_YOU`. On a directed booking the target accepts, this and `guard_id` end up the same guard.
  @BuiltValueField(wireName: r'target_guard_id')
  String? get targetGuardId;

  /// When the assigned guard STARTED work (stamped by PUT /bookings/{id}/start; the proration basis). null until started — clients restore the job clock from this after an app restart.
  @BuiltValueField(wireName: r'work_started_at')
  DateTime? get workStartedAt;

  /// When the PRE-PAY charge cleared (stamped by the payment.completed consumer). null = unpaid; the client uses this to know the accepted→en_route transition is gated (show the pay-step).
  @BuiltValueField(wireName: r'paid_at')
  DateTime? get paidAt;

  /// Why the booking ended early — the stable code supplied to cancel (`changed_plan`|`mistake`|`not_needed`|`other`) or decline (`emergency`|`sick`|`cannot_reach`|`other`); see `CancelBookingRequest` / `DeclineBookingRequest` for the labels. NEVER localized text: clients map the code to a label. Deliberately typed as a plain string, not an enum, so an unrecognized code degrades to \"ไม่ระบุ\"/\"Not specified\" instead of failing response decoding. null on active bookings, and on terminal rows created BEFORE the reason became mandatory (migration 0009).
  @BuiltValueField(wireName: r'cancellation_reason')
  String? get cancellationReason;

  /// The optional free-text detail that came with `cancellation_reason` (trimmed, ≤ 500 characters). null when none was given; always present when the reason is `other`.
  @BuiltValueField(wireName: r'cancellation_note')
  String? get cancellationNote;

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
    if (object.commissionPercent != null) {
      yield r'commission_percent';
      yield serializers.serialize(
        object.commissionPercent,
        specifiedType: const FullType(String),
      );
    }
    if (object.cancellationFee != null) {
      yield r'cancellation_fee';
      yield serializers.serialize(
        object.cancellationFee,
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
    if (object.targetGuardId != null) {
      yield r'target_guard_id';
      yield serializers.serialize(
        object.targetGuardId,
        specifiedType: const FullType(String),
      );
    }
    if (object.workStartedAt != null) {
      yield r'work_started_at';
      yield serializers.serialize(
        object.workStartedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.paidAt != null) {
      yield r'paid_at';
      yield serializers.serialize(
        object.paidAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.cancellationReason != null) {
      yield r'cancellation_reason';
      yield serializers.serialize(
        object.cancellationReason,
        specifiedType: const FullType(String),
      );
    }
    if (object.cancellationNote != null) {
      yield r'cancellation_note';
      yield serializers.serialize(
        object.cancellationNote,
        specifiedType: const FullType(String),
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
        case r'commission_percent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.commissionPercent = valueDes;
          break;
        case r'cancellation_fee':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cancellationFee = valueDes;
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
        case r'target_guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetGuardId = valueDes;
          break;
        case r'work_started_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.workStartedAt = valueDes;
          break;
        case r'paid_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.paidAt = valueDes;
          break;
        case r'cancellation_reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cancellationReason = valueDes;
          break;
        case r'cancellation_note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cancellationNote = valueDes;
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

