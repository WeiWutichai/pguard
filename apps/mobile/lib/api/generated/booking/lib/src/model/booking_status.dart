//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking_status.g.dart';

class BookingStatus extends EnumClass {

  /// Booking lifecycle status. See the state machine in src/domain/state.rs.
  @BuiltValueEnumConst(wireName: r'requested')
  static const BookingStatus requested = _$requested;
  /// Booking lifecycle status. See the state machine in src/domain/state.rs.
  @BuiltValueEnumConst(wireName: r'accepted')
  static const BookingStatus accepted = _$accepted;
  /// Booking lifecycle status. See the state machine in src/domain/state.rs.
  @BuiltValueEnumConst(wireName: r'declined')
  static const BookingStatus declined = _$declined;
  /// Booking lifecycle status. See the state machine in src/domain/state.rs.
  @BuiltValueEnumConst(wireName: r'en_route')
  static const BookingStatus enRoute = _$enRoute;
  /// Booking lifecycle status. See the state machine in src/domain/state.rs.
  @BuiltValueEnumConst(wireName: r'arrived')
  static const BookingStatus arrived = _$arrived;
  /// Booking lifecycle status. See the state machine in src/domain/state.rs.
  @BuiltValueEnumConst(wireName: r'pending_completion')
  static const BookingStatus pendingCompletion = _$pendingCompletion;
  /// Booking lifecycle status. See the state machine in src/domain/state.rs.
  @BuiltValueEnumConst(wireName: r'completed')
  static const BookingStatus completed = _$completed;
  /// Booking lifecycle status. See the state machine in src/domain/state.rs.
  @BuiltValueEnumConst(wireName: r'cancelled')
  static const BookingStatus cancelled = _$cancelled;

  static Serializer<BookingStatus> get serializer => _$bookingStatusSerializer;

  const BookingStatus._(String name): super(name);

  static BuiltSet<BookingStatus> get values => _$values;
  static BookingStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class BookingStatusMixin = Object with _$BookingStatusMixin;

