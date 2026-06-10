//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'payment_status.g.dart';

class PaymentStatus extends EnumClass {

  /// Payment lifecycle status.
  @BuiltValueEnumConst(wireName: r'pending')
  static const PaymentStatus pending = _$pending;
  /// Payment lifecycle status.
  @BuiltValueEnumConst(wireName: r'completed')
  static const PaymentStatus completed = _$completed;
  /// Payment lifecycle status.
  @BuiltValueEnumConst(wireName: r'refunded')
  static const PaymentStatus refunded = _$refunded;

  static Serializer<PaymentStatus> get serializer => _$paymentStatusSerializer;

  const PaymentStatus._(String name): super(name);

  static BuiltSet<PaymentStatus> get values => _$values;
  static PaymentStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class PaymentStatusMixin = Object with _$PaymentStatusMixin;

