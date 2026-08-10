//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_earning.g.dart';

/// One completed job's earning basis for the assigned guard. `actual_hours` is the clamped hours ACTUALLY worked (persisted at reconcile); `null` for an even-match / not-yet-reconciled row, where the client falls back to the booked hours. The client computes the guard's take from its own booking feed:   gross      = base_fee × actual_hours          (this guard's share — no guard_count, no tip)   commission = gross × commission_percent / 100   net        = gross − commission               ← what the guard is actually paid No VAT appears here: VAT is charged to the CUSTOMER on top of the bill and is not part of the guard's pay. 
///
/// Properties:
/// * [bookingId] 
/// * [actualHours] - Clamped hours actually worked (exact decimal as a string; money rule). Null when unreconciled.
/// * [commissionPercent] - The booking's SNAPSHOT commission percent (0–100, exact decimal string) DEDUCTED from this guard's gross for this job — the platform's cut, taken out of the guard's pay, not added to the customer's bill. null on pre-feature bookings → treat as 0 (guard keeps the full gross).
@BuiltValue()
abstract class GuardEarning implements Built<GuardEarning, GuardEarningBuilder> {
  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  /// Clamped hours actually worked (exact decimal as a string; money rule). Null when unreconciled.
  @BuiltValueField(wireName: r'actual_hours')
  String? get actualHours;

  /// The booking's SNAPSHOT commission percent (0–100, exact decimal string) DEDUCTED from this guard's gross for this job — the platform's cut, taken out of the guard's pay, not added to the customer's bill. null on pre-feature bookings → treat as 0 (guard keeps the full gross).
  @BuiltValueField(wireName: r'commission_percent')
  String? get commissionPercent;

  GuardEarning._();

  factory GuardEarning([void updates(GuardEarningBuilder b)]) = _$GuardEarning;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuardEarningBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardEarning> get serializer => _$GuardEarningSerializer();
}

class _$GuardEarningSerializer implements PrimitiveSerializer<GuardEarning> {
  @override
  final Iterable<Type> types = const [GuardEarning, _$GuardEarning];

  @override
  final String wireName = r'GuardEarning';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardEarning object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'booking_id';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
    if (object.actualHours != null) {
      yield r'actual_hours';
      yield serializers.serialize(
        object.actualHours,
        specifiedType: const FullType(String),
      );
    }
    if (object.commissionPercent != null) {
      yield r'commission_percent';
      yield serializers.serialize(
        object.commissionPercent,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GuardEarning object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardEarningBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'actual_hours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.actualHours = valueDes;
          break;
        case r'commission_percent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.commissionPercent = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuardEarning deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuardEarningBuilder();
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

