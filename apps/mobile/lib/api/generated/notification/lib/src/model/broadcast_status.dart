//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'broadcast_status.g.dart';

class BroadcastStatus extends EnumClass {

  @BuiltValueEnumConst(wireName: r'draft')
  static const BroadcastStatus draft = _$draft;
  @BuiltValueEnumConst(wireName: r'scheduled')
  static const BroadcastStatus scheduled = _$scheduled;
  @BuiltValueEnumConst(wireName: r'sent')
  static const BroadcastStatus sent = _$sent;

  static Serializer<BroadcastStatus> get serializer => _$broadcastStatusSerializer;

  const BroadcastStatus._(String name): super(name);

  static BuiltSet<BroadcastStatus> get values => _$values;
  static BroadcastStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class BroadcastStatusMixin = Object with _$BroadcastStatusMixin;

