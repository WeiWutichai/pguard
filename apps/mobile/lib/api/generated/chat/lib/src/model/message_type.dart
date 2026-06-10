//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'message_type.g.dart';

class MessageType extends EnumClass {

  /// Message kind. `image`/`video` carry the attachment reference/URL in `content`.
  @BuiltValueEnumConst(wireName: r'text')
  static const MessageType text = _$text;
  /// Message kind. `image`/`video` carry the attachment reference/URL in `content`.
  @BuiltValueEnumConst(wireName: r'image')
  static const MessageType image = _$image;
  /// Message kind. `image`/`video` carry the attachment reference/URL in `content`.
  @BuiltValueEnumConst(wireName: r'video')
  static const MessageType video = _$video;
  /// Message kind. `image`/`video` carry the attachment reference/URL in `content`.
  @BuiltValueEnumConst(wireName: r'system')
  static const MessageType system = _$system;

  static Serializer<MessageType> get serializer => _$messageTypeSerializer;

  const MessageType._(String name): super(name);

  static BuiltSet<MessageType> get values => _$values;
  static MessageType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class MessageTypeMixin = Object with _$MessageTypeMixin;

