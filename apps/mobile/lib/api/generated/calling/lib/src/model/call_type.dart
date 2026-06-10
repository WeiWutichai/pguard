//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'call_type.g.dart';

class CallType extends EnumClass {

  @BuiltValueEnumConst(wireName: r'audio')
  static const CallType audio = _$audio;
  @BuiltValueEnumConst(wireName: r'video')
  static const CallType video = _$video;

  static Serializer<CallType> get serializer => _$callTypeSerializer;

  const CallType._(String name): super(name);

  static BuiltSet<CallType> get values => _$values;
  static CallType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class CallTypeMixin = Object with _$CallTypeMixin;

