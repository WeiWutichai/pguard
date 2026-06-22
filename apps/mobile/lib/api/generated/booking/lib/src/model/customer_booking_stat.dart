//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'customer_booking_stat.g.dart';

/// Lifetime booking aggregate for one customer (web-admin customers page).
///
/// Properties:
/// * [customerId] 
/// * [total] - All bookings ever placed by this customer.
/// * [completed] - Bookings that reached the completed state.
/// * [cancelled] - Terminal not-done states (cancelled + declined).
@BuiltValue()
abstract class CustomerBookingStat implements Built<CustomerBookingStat, CustomerBookingStatBuilder> {
  @BuiltValueField(wireName: r'customer_id')
  String get customerId;

  /// All bookings ever placed by this customer.
  @BuiltValueField(wireName: r'total')
  int get total;

  /// Bookings that reached the completed state.
  @BuiltValueField(wireName: r'completed')
  int get completed;

  /// Terminal not-done states (cancelled + declined).
  @BuiltValueField(wireName: r'cancelled')
  int get cancelled;

  CustomerBookingStat._();

  factory CustomerBookingStat([void updates(CustomerBookingStatBuilder b)]) = _$CustomerBookingStat;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CustomerBookingStatBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CustomerBookingStat> get serializer => _$CustomerBookingStatSerializer();
}

class _$CustomerBookingStatSerializer implements PrimitiveSerializer<CustomerBookingStat> {
  @override
  final Iterable<Type> types = const [CustomerBookingStat, _$CustomerBookingStat];

  @override
  final String wireName = r'CustomerBookingStat';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CustomerBookingStat object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'customer_id';
    yield serializers.serialize(
      object.customerId,
      specifiedType: const FullType(String),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(int),
    );
    yield r'completed';
    yield serializers.serialize(
      object.completed,
      specifiedType: const FullType(int),
    );
    yield r'cancelled';
    yield serializers.serialize(
      object.cancelled,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CustomerBookingStat object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CustomerBookingStatBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'customer_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.customerId = valueDes;
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.total = valueDes;
          break;
        case r'completed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.completed = valueDes;
          break;
        case r'cancelled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.cancelled = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CustomerBookingStat deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CustomerBookingStatBuilder();
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

