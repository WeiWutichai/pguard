//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'audience.g.dart';

class Audience extends EnumClass {

  /// Broadcast target audience (resolved to recipients via profile).
  @BuiltValueEnumConst(wireName: r'all')
  static const Audience all = _$all;
  /// Broadcast target audience (resolved to recipients via profile).
  @BuiltValueEnumConst(wireName: r'guards')
  static const Audience guards = _$guards;
  /// Broadcast target audience (resolved to recipients via profile).
  @BuiltValueEnumConst(wireName: r'customers')
  static const Audience customers = _$customers;

  static Serializer<Audience> get serializer => _$audienceSerializer;

  const Audience._(String name): super(name);

  static BuiltSet<Audience> get values => _$values;
  static Audience valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class AudienceMixin = Object with _$AudienceMixin;

