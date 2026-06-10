//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_type.g.dart';

class NotificationType extends EnumClass {

  @BuiltValueEnumConst(wireName: r'booking_created')
  static const NotificationType bookingCreated = _$bookingCreated;
  @BuiltValueEnumConst(wireName: r'guard_assigned')
  static const NotificationType guardAssigned = _$guardAssigned;
  @BuiltValueEnumConst(wireName: r'guard_en_route')
  static const NotificationType guardEnRoute = _$guardEnRoute;
  @BuiltValueEnumConst(wireName: r'guard_arrived')
  static const NotificationType guardArrived = _$guardArrived;
  @BuiltValueEnumConst(wireName: r'booking_completed')
  static const NotificationType bookingCompleted = _$bookingCompleted;
  @BuiltValueEnumConst(wireName: r'booking_cancelled')
  static const NotificationType bookingCancelled = _$bookingCancelled;
  @BuiltValueEnumConst(wireName: r'chat_message')
  static const NotificationType chatMessage = _$chatMessage;
  @BuiltValueEnumConst(wireName: r'system')
  static const NotificationType system = _$system;

  static Serializer<NotificationType> get serializer => _$notificationTypeSerializer;

  const NotificationType._(String name): super(name);

  static BuiltSet<NotificationType> get values => _$values;
  static NotificationType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class NotificationTypeMixin = Object with _$NotificationTypeMixin;

