//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refund_source_kind.g.dart';

class RefundSourceKind extends EnumClass {

  /// WHICH table owes a refund obligation. `payment` = `payment.payments` (the completion-reconcile overpay, the cancellation refund, the race-lost pre-pay compensator); `slip` = `payment.payment_slips` (a genuine double-transfer for an already-paid booking). The two are separate tables with separate id spaces, so an obligation is always named by the PAIR. 
  @BuiltValueEnumConst(wireName: r'payment')
  static const RefundSourceKind payment = _$payment;
  /// WHICH table owes a refund obligation. `payment` = `payment.payments` (the completion-reconcile overpay, the cancellation refund, the race-lost pre-pay compensator); `slip` = `payment.payment_slips` (a genuine double-transfer for an already-paid booking). The two are separate tables with separate id spaces, so an obligation is always named by the PAIR. 
  @BuiltValueEnumConst(wireName: r'slip')
  static const RefundSourceKind slip = _$slip;

  static Serializer<RefundSourceKind> get serializer => _$refundSourceKindSerializer;

  const RefundSourceKind._(String name): super(name);

  static BuiltSet<RefundSourceKind> get values => _$values;
  static RefundSourceKind valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class RefundSourceKindMixin = Object with _$RefundSourceKindMixin;

