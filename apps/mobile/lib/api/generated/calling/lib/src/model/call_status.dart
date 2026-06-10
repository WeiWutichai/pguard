//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'call_status.g.dart';

class CallStatus extends EnumClass {

  @BuiltValueEnumConst(wireName: r'initiated')
  static const CallStatus initiated = _$initiated;
  @BuiltValueEnumConst(wireName: r'accepted')
  static const CallStatus accepted = _$accepted;
  @BuiltValueEnumConst(wireName: r'connected')
  static const CallStatus connected = _$connected;
  @BuiltValueEnumConst(wireName: r'ended')
  static const CallStatus ended = _$ended;
  @BuiltValueEnumConst(wireName: r'rejected')
  static const CallStatus rejected = _$rejected;
  @BuiltValueEnumConst(wireName: r'missed')
  static const CallStatus missed = _$missed;

  static Serializer<CallStatus> get serializer => _$callStatusSerializer;

  const CallStatus._(String name): super(name);

  static BuiltSet<CallStatus> get values => _$values;
  static CallStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class CallStatusMixin = Object with _$CallStatusMixin;

