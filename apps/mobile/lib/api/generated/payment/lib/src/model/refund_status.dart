//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refund_status.g.dart';

class RefundStatus extends EnumClass {

  /// Refund-workflow state (NOT the payment status — a partial refund stays `completed`).
  @BuiltValueEnumConst(wireName: r'pending')
  static const RefundStatus pending = _$pending;
  /// Refund-workflow state (NOT the payment status — a partial refund stays `completed`).
  @BuiltValueEnumConst(wireName: r'processed')
  static const RefundStatus processed = _$processed;

  static Serializer<RefundStatus> get serializer => _$refundStatusSerializer;

  const RefundStatus._(String name): super(name);

  static BuiltSet<RefundStatus> get values => _$values;
  static RefundStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class RefundStatusMixin = Object with _$RefundStatusMixin;

