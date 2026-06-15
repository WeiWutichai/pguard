//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'broadcast_mode.g.dart';

class BroadcastMode extends EnumClass {

  /// How a composed broadcast is dispatched.
  @BuiltValueEnumConst(wireName: r'now')
  static const BroadcastMode now = _$now;
  /// How a composed broadcast is dispatched.
  @BuiltValueEnumConst(wireName: r'draft')
  static const BroadcastMode draft = _$draft;
  /// How a composed broadcast is dispatched.
  @BuiltValueEnumConst(wireName: r'scheduled')
  static const BroadcastMode scheduled = _$scheduled;

  static Serializer<BroadcastMode> get serializer => _$broadcastModeSerializer;

  const BroadcastMode._(String name): super(name);

  static BuiltSet<BroadcastMode> get values => _$values;
  static BroadcastMode valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class BroadcastModeMixin = Object with _$BroadcastModeMixin;

